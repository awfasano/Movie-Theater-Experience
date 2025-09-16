import Foundation
import FirebaseFirestore
import _FirebaseFirestore_Swift // For @DocumentID

// Enhanced CalendarEvent for trivia/hosted events
struct CalendarEvent: Identifiable, Codable {
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

    // Computed properties
    var isHostedEvent: Bool { eventType != .space }
    var isFull: Bool { currentParticipants >= maxParticipants }
    var canJoin: Bool { status == .scheduled && !isFull }
}

enum EventType: String, CaseIterable, Codable {
    case space = "space"
    case hostedTrivia = "hosted_trivia"
    case hostedMovie = "hosted_movie"
    case hostedPresentation = "hosted_presentation"
}

enum EventStatus: String, Codable {
    case scheduled = "scheduled"
    case active = "active"
    case ended = "ended"
    case cancelled = "cancelled"
}

struct TableConfiguration: Codable {
    let maxTables: Int
    let maxSeatsPerTable: Int
    let layoutType: TableLayoutType
}

enum TableLayoutType: String, Codable {
    case circular = "circular"
    case classroom = "classroom"
    case theater = "theater"
}

struct GameConfiguration: Codable {
    let triviaGameId: String
    let totalRounds: Int
    let pointsPerQuestion: Int
    let questionTimeLimit: Int
}
