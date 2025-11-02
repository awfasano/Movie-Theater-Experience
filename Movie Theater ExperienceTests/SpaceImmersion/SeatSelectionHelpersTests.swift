import XCTest
@testable import Movie_Theater_Experience

final class SeatSelectionHelpersTests: XCTestCase {
    func testSeatSelectionPanelInitializesWithBinding() {
        var seat = "A1"
        let panel = SeatSelectionPanel(
            currentSeat: .init(get: { seat }, set: { seat = $0 }),
            onSeatSelected: { seat = $0 },
            availableSeats: ["A1", "A2"]
        )
        XCTAssertNotNil(panel)
    }
}
