import XCTest
import FirebaseFirestore
@testable import Movie_Theater_Experience

final class EventMessageHelperTests: XCTestCase {
    
    func testEventDateFormatterProducesExpectedString() {
        var components = DateComponents()
        components.year = 2025
        components.month = 10
        components.day = 24
        components.hour = 15
        components.minute = 45
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!
        
        let formatted = EventDateFormatter.string(from: date)
        XCTAssertEqual(formatted, "10-24-2025")
    }
    
    func testChatMessagePayloadBuilder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = EventMessagePayloadBuilder.chatMessage(
            text: "Hello",
            timestamp: now,
            senderId: "user123",
            senderName: "Tester"
        )
        
        XCTAssertEqual(payload["content"] as? String, "Hello")
        XCTAssertEqual(payload["senderId"] as? String, "user123")
        XCTAssertEqual(payload["senderName"] as? String, "Tester")
        XCTAssertEqual(payload["type"] as? Bool, true)
        let timestamp = payload["timestamp"] as? Timestamp
        XCTAssertEqual(timestamp?.dateValue(), now)
    }
    
    func testEmojiMessagePayloadBuilder() {
        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let payload = EventMessagePayloadBuilder.emojiMessage(
            emoji: 2,
            timestamp: now,
            senderId: "user456",
            senderName: "Emoji Tester",
            seatOrTheatre: false
        )
        
        XCTAssertEqual(payload["emoji"] as? Int, 2)
        XCTAssertEqual(payload["seatOrTheatre"] as? Bool, false)
        XCTAssertEqual(payload["type"] as? Bool, false)
        let timestamp = payload["timestamp"] as? Timestamp
        XCTAssertEqual(timestamp?.dateValue(), now)
    }
    
    func testEmojiImageMapperReturnsExpectedNames() {
        XCTAssertEqual(EmojiImageMapper.imageName(for: 0), "heart")
        XCTAssertEqual(EmojiImageMapper.imageName(for: 3), "laughter")
        XCTAssertEqual(EmojiImageMapper.imageName(for: 999), "heart")
    }
    
    func testEmojiEventFilterRespectsThreshold() {
        let start = Date()
        let filter = EmojiEventFilter(listenerStartTime: start, ageThreshold: 45)
        
        XCTAssertTrue(filter.isEmojiFresh(start.addingTimeInterval(-30)))
        XCTAssertFalse(filter.isEmojiFresh(start.addingTimeInterval(-60)))
    }
    
    func testEmojiEventFilterFailsWithoutStartTime() {
        let filter = EmojiEventFilter(listenerStartTime: nil, ageThreshold: 45)
        XCTAssertFalse(filter.isEmojiFresh(Date()))
    }
}
