import XCTest
import SwiftUI
@testable import Movie_Theater_Experience

@MainActor
final class ChatSupportTests: XCTestCase {
    
    func testChatMessageEqualityIsIdBased() {
        let date = Date()
        let first = ChatMessage(id: "id", timestamp: date, content: "A", senderId: "1", senderName: "User1")
        let second = ChatMessage(id: "id", timestamp: date.addingTimeInterval(10), content: "B", senderId: "2", senderName: "User2")
        let third = ChatMessage(id: "other", timestamp: date, content: "A", senderId: "1", senderName: "User1")
        
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)
    }
    
    func testMessagePositionTrackerStoresAndRetrievesFrames() {
        let tracker = MessagePositionTracker()
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        tracker.updateFrame(frame, for: "msg1")
        
        XCTAssertEqual(tracker.getFrame(for: "msg1"), frame)
        XCTAssertNil(tracker.getFrame(for: "missing"))
    }
    
    func testScrollOffsetPreferenceKeyUsesLatestValue() {
        var value = ScrollOffsetPreferenceKey.defaultValue
        ScrollOffsetPreferenceKey.reduce(value: &value) { 25 }
        XCTAssertEqual(value, 25)
        
        ScrollOffsetPreferenceKey.reduce(value: &value) { -5 }
        XCTAssertEqual(value, -5)
    }
    
    func testMessagePositionPreferenceKeyAppendsPositions() {
        var accumulated: [MessagePosition] = []
        let first = [MessagePosition(id: "1", position: 10)]
        let second = [MessagePosition(id: "2", position: 20)]
        
        accumulated = first
        MessagePositionPreferenceKey.reduce(value: &accumulated) { second }
        
        XCTAssertEqual(accumulated.count, 2)
        XCTAssertEqual(accumulated.last?.id, "2")
    }
}
