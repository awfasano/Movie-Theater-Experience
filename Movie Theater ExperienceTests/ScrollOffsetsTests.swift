import XCTest
import SwiftUI
@testable import Movie_Theater_Experience

final class ScrollOffsetsTests: XCTestCase {
    func testPreferenceKeyReduceUsesLatestValue() {
        var value: CGFloat = 10
        ScrollOffsetPreferenceKey.reduce(value: &value) { 25 }
        XCTAssertEqual(value, 25)
    }
}
