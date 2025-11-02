
import XCTest
@testable import Movie_Theater_Experience

class SeatPositionTests: XCTestCase {

    func testInitialization() {
        let seat = SeatPosition(id: "seat_1", x: 10.0, y: 20.0, isAvailable: true, label: "A1")
        XCTAssertEqual(seat.id, "seat_1")
        XCTAssertEqual(seat.x, 10.0)
        XCTAssertEqual(seat.y, 20.0)
        XCTAssertTrue(seat.isAvailable)
        XCTAssertEqual(seat.label, "A1")
    }

    func testCodable() throws {
        let seat = SeatPosition(id: "seat_2", x: 15.0, y: 25.0, isAvailable: false, label: "B2")
        let encoder = JSONEncoder()
        let data = try encoder.encode(seat)
        
        let decoder = JSONDecoder()
        let decodedSeat = try decoder.decode(SeatPosition.self, from: data)
        
        XCTAssertEqual(seat, decodedSeat)
        XCTAssertEqual(seat.x, decodedSeat.x)
        XCTAssertEqual(seat.y, decodedSeat.y)
        XCTAssertEqual(seat.isAvailable, decodedSeat.isAvailable)
        XCTAssertEqual(seat.label, decodedSeat.label)
    }

    func testEquatable() {
        let seat1 = SeatPosition(id: "seat_3", x: 0, y: 0)
        let seat2 = SeatPosition(id: "seat_3", x: 1, y: 1)
        let seat3 = SeatPosition(id: "seat_4", x: 0, y: 0)
        
        XCTAssertEqual(seat1, seat2)
        XCTAssertNotEqual(seat1, seat3)
    }
    
    func testPositionComputedProperty() {
        let seat = SeatPosition(id: "seat_5", x: 50.0, y: 100.0)
        let expectedPosition = CGPoint(x: 50.0, y: 100.0)
        XCTAssertEqual(seat.position, expectedPosition)
    }
}
