import Foundation
import Combine

@MainActor
final class CalendarService: ObservableObject {
    @Published var events: [CalendarEvent] = []

    init() { }

    /// Fetch all events (placeholder implementation)
    func fetchAllEvents() {
        // In a real implementation, load from Firestore or your backend.
        // For now, provide a small set of sample events so the UI can render.
        let now = Date()
        let inOneHour = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        let inTwoHours = Calendar.current.date(byAdding: .hour, value: 2, to: now) ?? now

        let sample1 = CalendarEvent(
            title: "Sample Space",
            description: "Welcome to the space",
            startTime: now,
            endTime: inOneHour,
            timeZone: TimeZone.current.identifier,
            eventType: .space,
            status: .scheduled
        )

        let sample2 = CalendarEvent(
            title: "Trivia Night",
            description: "Round 1 kicks off",
            startTime: inOneHour,
            endTime: inTwoHours,
            timeZone: TimeZone.current.identifier,
            eventType: .hostedTrivia,
            status: .scheduled
        )

        self.events = [sample1, sample2]
    }

    /// Fetch events for a specific date (placeholder)
    func fetchEvents(for date: Date) {
        // Filter the current events to those on the given date.
        let cal = Calendar.current
        events = events.filter { cal.isDate($0.startTime, inSameDayAs: date) }
    }
}
