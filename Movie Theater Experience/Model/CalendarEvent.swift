import Foundation
import FirebaseFirestore
import SwiftUI

// Enhanced CalendarEvent for trivia/hosted events
struct CalendarEvent: Identifiable, Codable, Equatable {
    @DocumentID var id: String?

    // Basic info
    var title: String
    var description: String
    var startTime: Date
    var endTime: Date
    var timeZone: String = "America/New_York"

    // Event type and status
    var eventType: EventType = .space
    var status: EventStatus = .scheduled

    // Capacity
    var maxParticipants: Int = 1000
    var currentParticipants: Int = 0
    var requiresRegistration: Bool = false

    // Host info
    var hostId: String?
    var hostName: String?
    var moderatorIds: [String] = []

    // Configuration
    var spaceId: String?
    var tableConfiguration: TableConfiguration?
    var gameConfig: GameConfiguration?
    
    // Media URLs (for non-trivia events)
    var videoURL: String?
    var thumbnailURL: String?

    // Computed properties
    var isHostedEvent: Bool { eventType != .space }
    var isFull: Bool { currentParticipants >= maxParticipants }
    var canJoin: Bool { status == .scheduled && !isFull }
    
    // MARK: - Additional Computed Properties for Compatibility
    
    /// Alias for startTime to maintain compatibility with existing code
    var date: Date { startTime }
    
    /// Alias for endTime to maintain compatibility with existing code
    var end: Date { endTime }
    
    /// Returns the video URL as a URL object if available
    var videoURLObject: URL? {
        guard let videoURL = videoURL, !videoURL.isEmpty else { return nil }
        return URL(string: videoURL)
    }
    
    /// Returns the appropriate color for the event type
    var eventColor: Color {
        switch eventType {
        case .space:
            return .purple
        case .hostedTrivia:
            return .blue
        case .hostedMovie:
            return .orange
        case .hostedPresentation:
            return .green
        }
    }
    
    /// Returns the appropriate icon for the event type
    var eventIcon: String {
        switch eventType {
        case .space:
            return "cube.fill"
        case .hostedTrivia:
            return "questionmark.circle.fill"
        case .hostedMovie:
            return "film.fill"
        case .hostedPresentation:
            return "person.crop.rectangle.fill"
        }
    }
    
    /// Checks if the event is currently happening
    var isHappeningNow: Bool {
        let now = Date()
        return now >= startTime && now <= endTime
    }
    
    /// Checks if the event has already ended
    var hasEnded: Bool {
        Date() > endTime
    }
    
    /// Checks if the event hasn't started yet
    var hasNotStarted: Bool {
        Date() < startTime
    }
    
    /// Returns formatted duration string
    var durationString: String {
        let duration = endTime.timeIntervalSince(startTime)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Returns a formatted string for the event time
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(identifier: timeZone)
        
        let startString = formatter.string(from: startTime)
        let endString = formatter.string(from: endTime)
        
        return "\(startString) - \(endString)"
    }
    
    /// Returns remaining capacity
    var remainingCapacity: Int {
        max(0, maxParticipants - currentParticipants)
    }
    
    /// Returns capacity percentage filled
    var capacityPercentage: Double {
        guard maxParticipants > 0 else { return 0 }
        return Double(currentParticipants) / Double(maxParticipants)
    }
    
    /// Checks if user is the host
    func isHost(userId: String) -> Bool {
        return hostId == userId
    }
    
    /// Checks if user is a moderator
    func isModerator(userId: String) -> Bool {
        return moderatorIds.contains(userId)
    }
    
    /// Checks if user has special privileges (host or moderator)
    func hasPrivileges(userId: String) -> Bool {
        return isHost(userId: userId) || isModerator(userId: userId)
    }
    
    // MARK: - Equatable
    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Supporting Types

enum EventType: String, CaseIterable, Codable {
    case space = "space"
    case hostedTrivia = "hosted_trivia"
    case hostedMovie = "hosted_movie"
    case hostedPresentation = "hosted_presentation"
    
    var displayName: String {
        switch self {
        case .space:
            return "Space"
        case .hostedTrivia:
            return "Trivia Night"
        case .hostedMovie:
            return "Movie Screening"
        case .hostedPresentation:
            return "Live Presentation"
        }
    }
}

enum EventStatus: String, Codable {
    case scheduled = "scheduled"
    case active = "active"
    case ended = "ended"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .scheduled:
            return "Scheduled"
        case .active:
            return "Active"
        case .ended:
            return "Ended"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    var color: Color {
        switch self {
        case .scheduled:
            return .blue
        case .active:
            return .green
        case .ended:
            return .gray
        case .cancelled:
            return .red
        }
    }
}

struct TableConfiguration: Codable {
    let maxTables: Int
    let maxSeatsPerTable: Int
    let layoutType: TableLayoutType
    
    var totalCapacity: Int {
        return maxTables * maxSeatsPerTable
    }
}

enum TableLayoutType: String, Codable {
    case circular = "circular"
    case classroom = "classroom"
    case theater = "theater"
    
    var displayName: String {
        switch self {
        case .circular:
            return "Circular Layout"
        case .classroom:
            return "Classroom Layout"
        case .theater:
            return "Theater Layout"
        }
    }
    
    var description: String {
        switch self {
        case .circular:
            return "Tables arranged in a circle for group discussion"
        case .classroom:
            return "Tables in rows facing the front"
        case .theater:
            return "Tables in a line facing the stage"
        }
    }
}

struct GameConfiguration: Codable {
    let triviaGameId: String
    let totalRounds: Int
    let pointsPerQuestion: Int
    let questionTimeLimit: Int
    
    var totalPossiblePoints: Int {
        // This would need to be calculated based on the actual game
        return totalRounds * 10 * pointsPerQuestion // Assuming 10 questions per round
    }
    
    var formattedTimeLimit: String {
        return "\(questionTimeLimit) seconds"
    }
}

// MARK: - CalendarEvent Extensions for Firebase

extension CalendarEvent {
    /// Creates a dictionary for Firebase upload
    func toFirebaseData() -> [String: Any] {
        var data: [String: Any] = [
            "title": title,
            "description": description,
            "startTime": Timestamp(date: startTime),
            "endTime": Timestamp(date: endTime),
            "timeZone": timeZone,
            "eventType": eventType.rawValue,
            "status": status.rawValue,
            "maxParticipants": maxParticipants,
            "currentParticipants": currentParticipants,
            "requiresRegistration": requiresRegistration
        ]
        
        // Add optional fields
        if let hostId = hostId {
            data["hostId"] = hostId
        }
        if let hostName = hostName {
            data["hostName"] = hostName
        }
        if !moderatorIds.isEmpty {
            data["moderatorIds"] = moderatorIds
        }
        if let spaceId = spaceId {
            data["spaceId"] = spaceId
        }
        if let videoURL = videoURL {
            data["videoURL"] = videoURL
        }
        if let thumbnailURL = thumbnailURL {
            data["thumbnailURL"] = thumbnailURL
        }
        
        // Add complex objects
        if let tableConfig = tableConfiguration {
            data["tableConfiguration"] = [
                "maxTables": tableConfig.maxTables,
                "maxSeatsPerTable": tableConfig.maxSeatsPerTable,
                "layoutType": tableConfig.layoutType.rawValue
            ]
        }
        
        if let gameConfig = gameConfig {
            data["gameConfig"] = [
                "triviaGameId": gameConfig.triviaGameId,
                "totalRounds": gameConfig.totalRounds,
                "pointsPerQuestion": gameConfig.pointsPerQuestion,
                "questionTimeLimit": gameConfig.questionTimeLimit
            ]
        }
        
        return data
    }
    
    /// Creates a CalendarEvent from Firebase document data
    static func from(documentData: [String: Any], documentId: String? = nil) -> CalendarEvent? {
        guard let title = documentData["title"] as? String,
              let description = documentData["description"] as? String,
              let startTimestamp = documentData["startTime"] as? Timestamp,
              let endTimestamp = documentData["endTime"] as? Timestamp else {
            return nil
        }
        
        var event = CalendarEvent(
            title: title,
            description: description,
            startTime: startTimestamp.dateValue(),
            endTime: endTimestamp.dateValue()
        )
        
        event.id = documentId
        
        // Parse optional fields
        if let timeZone = documentData["timeZone"] as? String {
            event.timeZone = timeZone
        }
        if let eventTypeRaw = documentData["eventType"] as? String,
           let eventType = EventType(rawValue: eventTypeRaw) {
            event.eventType = eventType
        }
        if let statusRaw = documentData["status"] as? String,
           let status = EventStatus(rawValue: statusRaw) {
            event.status = status
        }
        if let maxParticipants = documentData["maxParticipants"] as? Int {
            event.maxParticipants = maxParticipants
        }
        if let currentParticipants = documentData["currentParticipants"] as? Int {
            event.currentParticipants = currentParticipants
        }
        if let requiresRegistration = documentData["requiresRegistration"] as? Bool {
            event.requiresRegistration = requiresRegistration
        }
        if let hostId = documentData["hostId"] as? String {
            event.hostId = hostId
        }
        if let hostName = documentData["hostName"] as? String {
            event.hostName = hostName
        }
        if let moderatorIds = documentData["moderatorIds"] as? [String] {
            event.moderatorIds = moderatorIds
        }
        if let spaceId = documentData["spaceId"] as? String {
            event.spaceId = spaceId
        }
        if let videoURL = documentData["videoURL"] as? String {
            event.videoURL = videoURL
        }
        if let thumbnailURL = documentData["thumbnailURL"] as? String {
            event.thumbnailURL = thumbnailURL
        }
        
        // Parse complex objects
        if let tableConfigData = documentData["tableConfiguration"] as? [String: Any],
           let maxTables = tableConfigData["maxTables"] as? Int,
           let maxSeatsPerTable = tableConfigData["maxSeatsPerTable"] as? Int,
           let layoutTypeRaw = tableConfigData["layoutType"] as? String,
           let layoutType = TableLayoutType(rawValue: layoutTypeRaw) {
            event.tableConfiguration = TableConfiguration(
                maxTables: maxTables,
                maxSeatsPerTable: maxSeatsPerTable,
                layoutType: layoutType
            )
        }
        
        if let gameConfigData = documentData["gameConfig"] as? [String: Any],
           let triviaGameId = gameConfigData["triviaGameId"] as? String,
           let totalRounds = gameConfigData["totalRounds"] as? Int,
           let pointsPerQuestion = gameConfigData["pointsPerQuestion"] as? Int,
           let questionTimeLimit = gameConfigData["questionTimeLimit"] as? Int {
            event.gameConfig = GameConfiguration(
                triviaGameId: triviaGameId,
                totalRounds: totalRounds,
                pointsPerQuestion: pointsPerQuestion,
                questionTimeLimit: questionTimeLimit
            )
        }
        
        return event
    }
}
