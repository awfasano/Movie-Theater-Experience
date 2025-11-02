import XCTest
@testable import Movie_Theater_Experience

final class MessagePositionTests: XCTestCase {
    func testEquatableConformance() {
        let positionA = MessagePosition(id: "msg", position: 10)
        let positionB = MessagePosition(id: "msg", position: 10)
        let positionC = MessagePosition(id: "msg", position: 15)
        
        XCTAssertEqual(positionA, positionB)
        XCTAssertNotEqual(positionA, positionC)
    }
}
