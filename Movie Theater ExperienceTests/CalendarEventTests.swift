
import XCTest
import SwiftUI
@testable import Movie_Theater_Experience

class CalendarEventTests: XCTestCase {

    func testInitialization() {
        let date = Date()
        let event = CalendarEvent(id: "1", title: "Test Event", date: date, end: date, description: "A test event", color: 1, videoURL: "https://example.com/video.mp4")
        XCTAssertEqual(event.id, "1")
        XCTAssertEqual(event.title, "Test Event")
        XCTAssertEqual(event.date, date)
        XCTAssertEqual(event.end, date)
        XCTAssertEqual(event.description, "A test event")
        XCTAssertEqual(event.color, 1)
        XCTAssertEqual(event.videoURL, "https://example.com/video.mp4")
    }

    func testCodable() throws {
        let date = Date()
        let event = CalendarEvent(id: "2", title: "Another Event", date: date, end: date, description: "Another test", color: 2, videoURL: "https://example.com/another.mp4")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedEvent = try decoder.decode(CalendarEvent.self, from: data)
        
        XCTAssertEqual(event.id, decodedEvent.id)
        XCTAssertEqual(event.title, decodedEvent.title)
        XCTAssertEqual(event.description, decodedEvent.description)
        XCTAssertEqual(event.color, decodedEvent.color)
        XCTAssertEqual(event.videoURL, decodedEvent.videoURL)
    }

    func testEventColor() {
        let event1 = CalendarEvent(id: "", title: "", date: Date(), end: Date(), description: "", color: 1, videoURL: "")
        XCTAssertEqual(event1.eventColor, .red)
        
        let event2 = CalendarEvent(id: "", title: "", date: Date(), end: Date(), description: "", color: 2, videoURL: "")
        XCTAssertEqual(event2.eventColor, .green)
        
        let event3 = CalendarEvent(id: "", title: "", date: Date(), end: Date(), description: "", color: 3, videoURL: "")
        XCTAssertEqual(event3.eventColor, .blue)
        
        let event4 = CalendarEvent(id: "", title: "", date: Date(), end: Date(), description: "", color: 10, videoURL: "")
        XCTAssertEqual(event4.eventColor, .blue) // Default case
    }

    func testVideoURLObject() {
        let validEvent = CalendarEvent(id: "", title: "", date: Date(), end: Date(), description: "", color: 1, videoURL: "https://example.com/video.mp4")
        XCTAssertEqual(validEvent.videoURLObject, URL(string: "https://example.com/video.mp4"))
        
        let invalidEvent = CalendarEvent(id: "", title: "", date: Date(), end: Date(), description: "", color: 1, videoURL: "not a url")
        XCTAssertEqual(invalidEvent.videoURLObject, URL(string: "about:blank"))
    }
}
