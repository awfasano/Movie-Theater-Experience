import XCTest
@testable import Movie_Theater_Experience

final class SpaceImmersionSeatPositionTests: XCTestCase {
    
    func testPositionReturnsCGPoint() {
        let seat = SeatPosition(id: "seat_1", x: 10, y: 20, isAvailable: true, label: "Seat 1")
        XCTAssertEqual(seat.position.x, 10)
        XCTAssertEqual(seat.position.y, 20)
    }
    
    func testEquatableUsesId() {
        let seatA = SeatPosition(id: "seat_1", x: 0, y: 0)
        let seatB = SeatPosition(id: "seat_1", x: 5, y: 5)
        XCTAssertEqual(seatA, seatB)
    }
}
