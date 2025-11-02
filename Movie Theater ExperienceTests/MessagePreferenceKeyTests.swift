import XCTest
@testable import Movie_Theater_Experience

final class MessagePreferenceKeyTests: XCTestCase {
    func testReduceAppendsIncomingValues() {
        var currentValue: [MessagePosition] = [MessagePosition(id: "a", position: 1)]
        let incoming = [MessagePosition(id: "b", position: 2)]
        
        MessagePositionPreferenceKey.reduce(value: &currentValue) { incoming }
        
        XCTAssertEqual(currentValue.count, 2)
        XCTAssertTrue(currentValue.contains(where: { $0.id == "b" }))
    }
}
