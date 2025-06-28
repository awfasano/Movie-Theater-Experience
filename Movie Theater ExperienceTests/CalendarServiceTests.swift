
import XCTest
@testable import Movie_Theater_Experience

class CalendarServiceTests: XCTestCase {

    var calendarService: CalendarService!

    override func setUp() {
        super.setUp()
        calendarService = CalendarService()
    }

    override func tearDown() {
        calendarService = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(calendarService)
    }

    func testFetchAllEvents() {
        // This is difficult to test without a mock Firestore.
        // We would need to inject a mock Firestore instance into CalendarService
        // to properly test this functionality.
    }

    func testFetchEventsForDate() {
        // This is also difficult to test without a mock Firestore.
    }
}
