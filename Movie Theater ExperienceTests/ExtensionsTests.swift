import XCTest
import SwiftUI
@testable import Movie_Theater_Experience

final class UtilitiesExtensionsTests: XCTestCase {

    func testColorHexInitializerParsesValidString() {
        let color = Color(hex: "#FF0000")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.toHex, "#FF0000")
    }

    func testColorHexInitializerTrimsWhitespaceAndHandlesLowercase() {
        let color = Color(hex: "  00ff00")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.toHex, "#00FF00")
    }

    func testColorHexInitializerReturnsNilForInvalidLength() {
        XCTAssertNil(Color(hex: "#FFF"))
        XCTAssertNil(Color(hex: ""))
    }

    func testFloat4x4LookAtSetsTranslation() {
        let origin = SIMD3<Float>(1, 2, 3)
        let target = SIMD3<Float>(1, 2, 2)
        let matrix = float4x4(lookAt: origin, target: target, up: SIMD3<Float>(0, 1, 0))

        XCTAssertEqual(matrix.columns.3.x, origin.x, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.y, origin.y, accuracy: 0.0001)
        XCTAssertEqual(matrix.columns.3.z, origin.z, accuracy: 0.0001)
    }

    func testDaysInMonthReturnsAllDaysForLeapYearFebruary() {
        var components = DateComponents()
        components.year = 2024
        components.month = 2
        components.day = 10
        components.calendar = Calendar.current

        let date = components.date!
        let days = date.daysInMonth()
        XCTAssertEqual(days.count, 29)

        let calendar = Calendar.current
        let firstDay = calendar.component(.day, from: days.first!)
        let lastDay = calendar.component(.day, from: days.last!)
        XCTAssertEqual(firstDay, 1)
        XCTAssertEqual(lastDay, 29)
    }

    func testStartOfMonthResetsToFirstDay() {
        var components = DateComponents()
        components.year = 2025
        components.month = 10
        components.day = 24
        components.calendar = Calendar.current

        let date = components.date!
        let start = date.startOfMonth

        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: start), 1)
        XCTAssertEqual(calendar.component(.month, from: start), 10)
        XCTAssertEqual(calendar.component(.year, from: start), 2025)
    }
}
