import XCTest
@testable import Movie_Theater_Experience

final class CardChromeBackgroundTests: XCTestCase {
    func testCardChromeBackgroundInitDoesNotCrash() {
        let background = CardChromeBackground(isHighlighted: true, corner: 24)
        XCTAssertNotNil(background)
    }
}
