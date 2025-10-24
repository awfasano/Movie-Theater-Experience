//
//  EventsCalendarView.swift
//  Movie Theater Experience
//
//  Calendar view showing all trivia events
//

import SwiftUI
import FirebaseFirestore


struct SheetErrorFallback: View {
    @Environment(\.dismiss) private var dismiss
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct EventsCalendarView: View {
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var selectedEvent: CalendarEvent?
    @State private var showEventJoinFlow = false
    @State private var showTestDataGenerator = false
    @State private var currentMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @EnvironmentObject private var hostedEventManager: HostedEventManager

    private let db = FirebaseEventManager.uploadsDb
    private let calendar = Calendar.current

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    loadingView
                        .padding(.top, 80)
                } else {
                    VStack(spacing: 24) {
                        calendarHeader
                        weekdayHeader
                        calendarGrid
                        Divider()
                        dayDetailSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await loadEvents() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button {
                            showTestDataGenerator = true
                        } label: {
                            Label("Test Data", systemImage: "testtube.2")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showEventJoinFlow, onDismiss: {
                selectedEvent = nil
            }) {
                if let event = selectedEvent {
                    EventJoinFlowView(event: event)
                        .environmentObject(hostedEventManager)
                } else {
                    SheetErrorFallback(
                        message: "The selected event could not be loaded. Please refresh the calendar or choose another event."
                    )
                }
            }
            .sheet(isPresented: $showTestDataGenerator) {
                TestDataGeneratorView {
                    Task { await loadEvents() }
                }
            }
        }
        .onAppear {
            Task { await loadEvents() }
        }
    }

    // MARK: - Calendar Layout

    private var calendarHeader: some View {
        HStack(alignment: .center) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    moveMonth(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
            }

            Spacer()

            VStack(spacing: 4) {
                Text(monthFormatter.string(from: currentMonth))
                    .font(.title2.bold())

                Text(monthSummaryText())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    moveMonth(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
            }
        }
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(calendarDays) { day in
                dayCell(for: day)
            }
        }
    }

    private func dayCell(for day: CalendarDay) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day.date)
        let eventDots = Array(day.events.prefix(3))

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = calendar.startOfDay(for: day.date)
                if !day.isWithinDisplayedMonth {
                    currentMonth = calendar.startOfMonth(for: day.date)
                }
            }
        } label: {
            VStack(spacing: 6) {
                Text(dayNumberFormatter.string(from: day.date))
                    .font(isSelected ? .headline : .body)
                    .foregroundColor(
                        isSelected
                        ? .white
                        : (day.isWithinDisplayedMonth ? .primary : .secondary.opacity(0.4))
                    )
                    .frame(maxWidth: .infinity)

                if !eventDots.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(0..<eventDots.count, id: \.self) { index in
                            Circle()
                                .fill(eventDots[index].eventColor)
                                .frame(width: 6, height: 6)
                        }

                        if day.events.count > eventDots.count {
                            Text("+\(day.events.count - eventDots.count)")
                                .font(.caption2)
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                    }
                } else {
                    Color.clear
                        .frame(height: 6)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    } else if !day.isWithinDisplayedMonth {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.08))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var dayDetailSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detailDateFormatter.string(from: selectedDate))
                        .font(.title3.bold())
                    Text(daySummaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Today") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        goToToday()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(calendar.isDateInToday(selectedDate))
            }

            if eventsForSelectedDate.isEmpty {
                ContentUnavailableView(
                    "No events",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("There are no scheduled events for this day.")
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 16) {
                    ForEach(eventsForSelectedDate) { event in
                        EventCard(event: event) {
                            selectedEvent = event
                            showEventJoinFlow = true
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading events...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Calendar Helpers

    private var daySummaryText: String {
        let count = eventsForSelectedDate.count
        switch count {
        case 0:
            return "No scheduled events"
        case 1:
            return "1 event scheduled"
        default:
            return "\(count) events scheduled"
        }
    }

    private var eventsForSelectedDate: [CalendarEvent] {
        eventsForDate(selectedDate)
    }

    private var eventsInCurrentMonth: [CalendarEvent] {
        events.filter {
            calendar.isDate($0.startTime, equalTo: currentMonth, toGranularity: .month)
        }
    }

    private var calendarDays: [CalendarDay] {
        let startOfMonth = calendar.startOfMonth(for: currentMonth)
        guard let daysRange = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return []
        }

        let firstWeekdayIndex = calendar.firstWeekday
        let firstDayWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadingDays = (firstDayWeekday - firstWeekdayIndex + 7) % 7

        var days: [CalendarDay] = []

        if leadingDays > 0,
           let previousMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth),
           let previousRange = calendar.range(of: .day, in: .month, for: previousMonth) {
            let startDay = previousRange.count - leadingDays + 1
            for day in startDay...previousRange.count {
                if let date = calendar.date(bySetting: .day, value: day, of: previousMonth) {
                    let normalized = calendar.startOfDay(for: date)
                    days.append(CalendarDay(date: normalized, isWithinDisplayedMonth: false, events: eventsForDate(normalized)))
                }
            }
        }

        for day in daysRange {
            if let date = calendar.date(bySetting: .day, value: day, of: startOfMonth) {
                let normalized = calendar.startOfDay(for: date)
                days.append(CalendarDay(date: normalized, isWithinDisplayedMonth: true, events: eventsForDate(normalized)))
            }
        }

        let totalCells = days.count
        let trailingDays = (7 - (totalCells % 7)) % 7

        if trailingDays > 0,
           let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) {
            for day in 1...trailingDays {
                if let date = calendar.date(bySetting: .day, value: day, of: nextMonth) {
                    let normalized = calendar.startOfDay(for: date)
                    days.append(CalendarDay(date: normalized, isWithinDisplayedMonth: false, events: eventsForDate(normalized)))
                }
            }
        }

        return days
    }

    private var weekdaySymbols: [String] {
        var symbols = calendar.shortStandaloneWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
        if firstWeekdayIndex > 0 {
            symbols = Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])
        }
        return symbols.map { $0.uppercased() }
    }

    private func eventsForDate(_ date: Date) -> [CalendarEvent] {
        events.filter { calendar.isDate($0.startTime, inSameDayAs: date) }
    }

    private func moveMonth(by value: Int) {
        let targetDate = calendar.date(byAdding: .month, value: value, to: selectedDate) ?? selectedDate
        currentMonth = calendar.startOfMonth(for: targetDate)
        selectedDate = calendar.startOfDay(for: targetDate)
    }

    private func goToToday() {
        let today = calendar.startOfDay(for: Date())
        currentMonth = calendar.startOfMonth(for: today)
        selectedDate = today
    }

    private func monthSummaryText() -> String {
        let count = eventsInCurrentMonth.count
        switch count {
        case 0:
            return "No scheduled events this month"
        case 1:
            return "1 event this month"
        default:
            return "\(count) events this month"
        }
    }

    private func alignSelectionWithData() {
        let today = calendar.startOfDay(for: Date())

        if calendar.isDate(selectedDate, equalTo: currentMonth, toGranularity: .month) {
            return
        }

        if calendar.isDate(today, equalTo: currentMonth, toGranularity: .month) {
            selectedDate = today
            return
        }

        if let firstEvent = events.sorted(by: { $0.startTime < $1.startTime }).first {
            let eventDate = calendar.startOfDay(for: firstEvent.startTime)
            currentMonth = calendar.startOfMonth(for: eventDate)
            selectedDate = eventDate
        } else {
            selectedDate = calendar.startOfDay(for: currentMonth)
        }
    }

    // MARK: - Data Loading

    private func loadEvents() async {
        await MainActor.run {
            isLoading = true
        }

        do {
            let snapshot = try await db.collection("Events")
                .whereField("eventType", isEqualTo: "hosted_trivia")
                .getDocuments()

            let loadedEvents = snapshot.documents.compactMap { doc -> CalendarEvent? in
                guard let event = CalendarEvent.from(documentData: doc.data(), documentId: doc.documentID) else {
                    return nil
                }
                return (event.status == .scheduled || event.status == .active) ? event : nil
            }.sorted { $0.startTime < $1.startTime }

            await MainActor.run {
                events = loadedEvents
                isLoading = false
                alignSelectionWithData()
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: CalendarEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: event.eventIcon)
                        .font(.title2)
                        .foregroundColor(event.eventColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(event.eventType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Status badge
                    StatusBadge(status: event.status)
                }

                Divider()

                // Details
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        Text(event.formattedTimeRange)
                            .font(.subheadline)
                        Spacer()
                        Text(event.durationString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "person.2")
                            .foregroundColor(.secondary)
                        Text("\(event.currentParticipants)/\(event.maxParticipants) participants")
                            .font(.subheadline)
                        Spacer()
                        if event.isHappeningNow {
                            Text("LIVE")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }

                    if let hostName = event.hostName {
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .foregroundColor(.secondary)
                            Text("Hosted by \(hostName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Description
                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Join button
                HStack {
                    Spacer()
                    Text("Join Event →")
                        .font(.subheadline.bold())
                        .foregroundColor(event.eventColor)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(event.eventColor.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
            .background(.regularMaterial)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: EventStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color)
            .cornerRadius(8)
    }
}

// MARK: - Calendar Helpers

private struct CalendarDay: Identifiable {
    let date: Date
    let isWithinDisplayedMonth: Bool
    let events: [CalendarEvent]

    var id: Date { date }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}

// MARK: - Preview

#if DEBUG
struct EventsCalendarView_Previews: PreviewProvider {
    static var previews: some View {
        EventsCalendarView()
            .environmentObject(HostedEventManager.shared)
    }
}
#endif
