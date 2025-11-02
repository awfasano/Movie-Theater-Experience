import XCTest
import SwiftUI
@testable import Movie_Theater_Experience

final class SeatButtonStyleTests: XCTestCase {
    func testSeatButtonStyleSelectedConfiguration() {
        let style = SeatButtonStyle(isSelected: true)
        XCTAssertNotNil(style)
    }
}
