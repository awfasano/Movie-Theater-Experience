import Foundation
import FirebaseFirestore

enum EventDateFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

enum EventMessagePayloadBuilder {
    static func chatMessage(
        text: String,
        timestamp: Date = Date(),
        senderId: String,
        senderName: String
    ) -> [String: Any] {
        [
            "content": text,
            "timestamp": Timestamp(date: timestamp),
            "senderId": senderId,
            "senderName": senderName,
            "type": true
        ]
    }
    
    static func emojiMessage(
        emoji: Int,
        timestamp: Date = Date(),
        senderId: String,
        senderName: String,
        seatOrTheatre: Bool
    ) -> [String: Any] {
        [
            "timestamp": Timestamp(date: timestamp),
            "senderId": senderId,
            "senderName": senderName,
            "emoji": emoji,
            "seatOrTheatre": seatOrTheatre,
            "type": false
        ]
    }
}

struct EmojiEventFilter {
    let listenerStartTime: Date?
    let ageThreshold: TimeInterval
    
    func isEmojiFresh(_ emojiTimestamp: Date) -> Bool {
        guard let start = listenerStartTime else { return false }
        let age = start.timeIntervalSince(emojiTimestamp)
        return age <= ageThreshold
    }
}

enum EmojiImageMapper {
    static func imageName(for emojiNumber: Int) -> String {
        switch emojiNumber {
        case 0: return "heart"
        case 1: return "crying"
        case 2: return "heart eyes"
        case 3: return "laughter"
        case 4: return "oh"
        default: return "heart"
        }
    }
}
