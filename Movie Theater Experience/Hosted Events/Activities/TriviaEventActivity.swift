import Foundation
import GroupActivities

@available(visionOS 1.0, *)
struct TriviaEventActivity: GroupActivity {
    let eventId: String
    let eventTitle: String
    let spaceId: String
    let sessionCode: String
    
    // FIXED: Use a consistent static identifier
    static let activityIdentifier = "com.waitedco.spiera.triviaEvent"
    
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .generic
        metadata.title = eventTitle
        metadata.subtitle = "Join the trivia tables"
        
        return metadata
    }
    
    // MARK: - Initialization
    
    init(eventId: String, eventTitle: String, spaceId: String) {
        self.eventId = eventId
        self.eventTitle = eventTitle
        self.spaceId = spaceId
        self.sessionCode = Self.generateSessionCode(for: eventId)
    }
    
    init(eventId: String, eventTitle: String, spaceId: String, sessionCode: String) {
        self.eventId = eventId
        self.eventTitle = eventTitle
        self.spaceId = spaceId
        self.sessionCode = sessionCode
    }
    
    // MARK: - Room Code Generation
    
    static func generateSessionCode(for eventId: String) -> String {
        let cleanEventId = eventId.replacingOccurrences(of: "-", with: "").uppercased()
        
        if cleanEventId.count >= 6 {
            return String(cleanEventId.prefix(6))
        } else {
            let paddedId = (cleanEventId + "TRIVIA").prefix(6)
            return String(paddedId)
        }
    }
    
    static func generateTableRoomCode(sessionCode: String, tableNumber: Int) -> String {
        return "\(sessionCode)T\(String(format: "%02d", tableNumber))"
    }
    
    static func generateHostRoomCode(sessionCode: String) -> String {
        return "\(sessionCode)HOST"
    }
    
    // MARK: - FaceTime URL Generation
    // NOTE: FaceTime URLs are now stored in Firebase as real Apple FaceTime Links.
    // These room code generation methods are kept for Firebase document tracking only.
    // Use HostedEventManager or HostAudioManager to retrieve actual FaceTime link URLs.
}
