//
//  helpersTests.swift
//  Movie Theater ExperienceTests
//
//  Created by Anthony Fasano on 5/23/25.
//

import Foundation
@testable import Movie_Theater_Experience // Make sure this is your app's module name
import XCTest


/// Returns an event that is “live now” and lasts another hour
func makeCurrentEvent(id: String,
                      videoURL: String = "about:blank") -> CalendarEvent {
    let now = Date()
    return CalendarEvent(id: id,
                         title: id,
                         date: now.addingTimeInterval(-60),      // started 1 min ago
                         end:  now.addingTimeInterval(+3600),    // ends in 1 h
                         description: "live",
                         color: 1,
                         videoURL: videoURL)                     // <-- never nil
}

///  Create an event that’s “live” (started 1 min ago, ends in 1 h)
func makeLiveEvent(id: String) -> CalendarEvent {
    let now = Date()
    return CalendarEvent(id: id,
                         title: id,
                         date: now.addingTimeInterval(-60),
                         end:  now.addingTimeInterval(+3600),
                         description: "live",
                         color: 1,
                         videoURL: "about:blank")
}

///  Poll every 100 ms until `predicate()` is true or `timeout` seconds elapse.
func poll(until predicate: @escaping () -> Bool,
          timeout: TimeInterval,
          file: StaticString = #file, line: UInt = #line) async throws {
    let start = Date()
    while !predicate() {
        if Date().timeIntervalSince(start) > timeout {
            XCTFail("poll timed out", file: file, line: line); return
        }
        try await Task.sleep(for: .milliseconds(100))
    }
}

func poll19(
    until predicate: @escaping () async throws -> Bool, // MODIFIED: Predicate is now async throws
    timeout: TimeInterval,
    description: String? = nil, // Optional: Added description for better XCTFail messages
    file: StaticString = #file,
    line: UInt = #line
) async throws {
    let start = Date()
    while true { // Loop indefinitely until condition met or timeout
        // Check if predicate is met
        if try await predicate() { // MODIFIED: Await the predicate
            if let desc = description {
                print("✅ Poll condition met: \(desc)")
            }
            return // Condition met, exit successfully
        }

        // Check for timeout
        if Date().timeIntervalSince(start) > timeout {
            let message = "Poll timed out" + (description.map { ": \($0)" } ?? "")
            XCTFail(message, file: file, line: line)
            // Optionally, throw a specific timeout error to make tests fail more explicitly if XCTFail isn't enough
            struct PollTimeoutError: Error { let message: String }
            throw PollTimeoutError(message: message) // Or just return to let XCTFail handle it
        }
        
        // Wait before next check
        try await Task.sleep(for: .milliseconds(100))
    }
}

func formattedDateForPath(date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd-yyyy"
    // Ensure this matches the timezone used in your VideoSyncService's getBasePath()
    // If getBasePath() uses event.date, pass that specific date here.
    formatter.timeZone = TimeZone(identifier: "EST") // Example, adjust if needed
    return formatter.string(from: date)
}


