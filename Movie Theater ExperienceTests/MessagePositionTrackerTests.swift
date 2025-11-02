import XCTest
import CoreGraphics
@testable import Movie_Theater_Experience

final class MessagePositionTrackerTests: XCTestCase {
    func testUpdateAndRetrieveFrame() {
        let tracker = MessagePositionTracker()
        let frame = CGRect(x: 10, y: 20, width: 30, height: 40)
        
        tracker.updateFrame(frame, for: "msg-1")
        
        XCTAssertEqual(tracker.getFrame(for: "msg-1"), frame)
    }
    
    func testGetFrameReturnsNilForUnknownMessage() {
        let tracker = MessagePositionTracker()
        XCTAssertNil(tracker.getFrame(for: "unknown"))
    }
}
