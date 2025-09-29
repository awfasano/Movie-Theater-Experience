//
//  TriviaEventActivties.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import GroupActivities

@available(visionOS 1.0, *)
struct TriviaEventActivity: GroupActivity {
    let eventId: String
    let eventTitle: String
    let spaceId: String
    let sessionCode: String // NEW: Room code for voice chat coordination
    
    var activityIdentifier: String {
        "com.waitedco.spiera.triviaEvent.\(eventId)"
    }
    
    var displayName: String { eventTitle }
    var subtitle: String? { "Join the trivia tables" }
    
    static let activityIdentifier = "com.waitedco.spiera.triviaEvent"
    
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .generic
        metadata.title = displayName
        metadata.subtitle = subtitle
        
        return metadata
    }
    
    // NEW: Convenience initializer with auto-generated session code
    init(eventId: String, eventTitle: String, spaceId: String) {
        self.eventId = eventId
        self.eventTitle = eventTitle
        self.spaceId = spaceId
        self.sessionCode = Self.generateSessionCode(for: eventId)
    }
    
    // NEW: Manual initializer if you want to specify session code
    init(eventId: String, eventTitle: String, spaceId: String, sessionCode: String) {
        self.eventId = eventId
        self.eventTitle = eventTitle
        self.spaceId = spaceId
        self.sessionCode = sessionCode
    }
    
    // MARK: - Room Code Generation
    
    /// Generate a consistent 6-character session code for an event
    /// This ensures everyone joining the same event gets the same code
    static func generateSessionCode(for eventId: String) -> String {
        // Use the first 6 characters of the event ID, or generate deterministically
        let cleanEventId = eventId.replacingOccurrences(of: "-", with: "").uppercased()
        
        if cleanEventId.count >= 6 {
            return String(cleanEventId.prefix(6))
        } else {
            // Pad with deterministic characters if event ID is too short
            let paddedId = (cleanEventId + "TRIVIA").prefix(6)
            return String(paddedId)
        }
    }
    
    /// Generate table-specific room codes
    static func generateTableRoomCode(sessionCode: String, tableNumber: Int) -> String {
        return "\(sessionCode)T\(String(format: "%02d", tableNumber))"
    }
    
    /// Generate host broadcast room code
    static func generateHostRoomCode(sessionCode: String) -> String {
        return "\(sessionCode)HOST"
    }
    
    // MARK: - FaceTime URL Generation
    
    /// Generate FaceTime room URL for a specific table
    func faceTimeURL(for tableNumber: Int) -> URL? {
        let tableRoomCode = Self.generateTableRoomCode(sessionCode: sessionCode, tableNumber: tableNumber)
        return URL(string: "facetime://room/\(tableRoomCode)")
    }
    
    /// Generate FaceTime URL for host broadcast
    func hostBroadcastURL() -> URL? {
        let hostRoomCode = Self.generateHostRoomCode(sessionCode: sessionCode)
        return URL(string: "facetime://room/\(hostRoomCode)")
    }
    
    /// Generate FaceTime URL for the main event room
    func mainEventURL() -> URL? {
        return URL(string: "facetime://room/\(sessionCode)")
    }
    
    // MARK: - Room Discovery
    
    /// Get all room codes that participants should be aware of
    func getAllRoomCodes(tableCount: Int) -> [String: String] {
        var rooms: [String: String] = [:]
        
        // Main event room
        rooms["main"] = sessionCode
        
        // Host broadcast room
        rooms["host"] = Self.generateHostRoomCode(sessionCode: sessionCode)
        
        // Table rooms
        for tableNumber in 1...tableCount {
            let tableRoomCode = Self.generateTableRoomCode(sessionCode: sessionCode, tableNumber: tableNumber)
            rooms["table_\(tableNumber)"] = tableRoomCode
        }
        
        return rooms
    }
}

// MARK: - Room Code Utilities

extension TriviaEventActivity {
    
    /// Validate if a room code belongs to this session
    func isValidRoomCode(_ roomCode: String) -> Bool {
        return roomCode.hasPrefix(sessionCode)
    }
    
    /// Extract table number from a table room code
    func extractTableNumber(from roomCode: String) -> Int? {
        let expectedPrefix = "\(sessionCode)T"
        guard roomCode.hasPrefix(expectedPrefix) else { return nil }
        
        let tableNumberString = String(roomCode.dropFirst(expectedPrefix.count))
        return Int(tableNumberString)
    }
    
    /// Check if room code is the host broadcast room
    func isHostRoom(_ roomCode: String) -> Bool {
        return roomCode == Self.generateHostRoomCode(sessionCode: sessionCode)
    }
    
    /// Get display name for a room code
    func displayName(for roomCode: String) -> String {
        if roomCode == sessionCode {
            return "Main Event"
        } else if isHostRoom(roomCode) {
            return "Host Broadcast"
        } else if let tableNumber = extractTableNumber(from: roomCode) {
            return "Table \(tableNumber)"
        } else {
            return "Unknown Room"
        }
    }
}
