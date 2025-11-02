import XCTest
@testable import Movie_Theater_Experience

final class DaySelectionLogicTests: XCTestCase {
    
    private var calendar: Calendar!
    private var calculator: DaySelectionStyleCalculator!
    private var today: Date!
    
    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calculator = DaySelectionStyleCalculator(calendar: calendar)
        today = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!
    }
    
    func testTextStyleTodaySelected() {
        let style = calculator.textStyle(for: today, currentDate: today)
        XCTAssertEqual(style, .todaySelected)
    }
    
    func testTextStyleTodayButNotSelected() {
        let currentDate = calendar.date(byAdding: .day, value: 1, to: today)!
        let style = calculator.textStyle(for: today, currentDate: currentDate)
        XCTAssertEqual(style, .today)
    }
    
    func testTextStyleSelectedNonToday() {
        let otherDay = calendar.date(byAdding: .day, value: -1, to: today)!
        let style = calculator.textStyle(for: otherDay, currentDate: otherDay)
        XCTAssertEqual(style, .selected)
    }
    
    func testTextStyleNormal() {
        let anotherDay = calendar.date(byAdding: .day, value: -2, to: today)!
        let style = calculator.textStyle(for: anotherDay, currentDate: today)
        XCTAssertEqual(style, .normal)
    }
    
    func testIsTodayRespectsCalendar() {
        XCTAssertTrue(calculator.isToday(today))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        XCTAssertFalse(calculator.isToday(tomorrow))
    }
    
}
