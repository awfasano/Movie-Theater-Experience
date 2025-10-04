//
//  EventsCalendarView.swift
//  Movie Theater Experience
//
//  Calendar view showing all trivia events
//

import SwiftUI
import FirebaseFirestore

struct EventsCalendarView: View {
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var selectedEvent: CalendarEvent?
    @State private var showEventJoinFlow = false
    @State private var showTestDataGenerator = false

    private let db = FirebaseEventManager.uploadsDb

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    if isLoading {
                        loadingView
                    } else if events.isEmpty {
                        emptyStateView
                    } else {
                        eventsListSection
                    }
                }
                .padding()
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task {
                                await loadEvents()
                            }
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
            .sheet(isPresented: $showEventJoinFlow) {
                if let event = selectedEvent {
                    EventJoinFlowView(event: event)
                }
            }
            .sheet(isPresented: $showTestDataGenerator) {
                TestDataGeneratorView()
            }
        }
        .onAppear {
            Task {
                await loadEvents()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Upcoming Events")
                .font(.title2.bold())

            Text("Join trivia nights, movie screenings, and more")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading events...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Events Available")
                .font(.headline)

            Text("Check back later or create test data to get started")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Create Test Event") {
                showTestDataGenerator = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Events List

    private var eventsListSection: some View {
        LazyVStack(spacing: 16) {
            ForEach(groupedEvents.keys.sorted(), id: \.self) { date in
                Section {
                    ForEach(groupedEvents[date] ?? []) { event in
                        EventCard(event: event) {
                            selectedEvent = event
                            showEventJoinFlow = true
                        }
                    }
                } header: {
                    HStack {
                        Text(formatSectionDate(date))
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var groupedEvents: [Date: [CalendarEvent]] {
        let grouped = Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.startTime)
        }
        print("📊 [Events] Grouped events: \(grouped.count) groups")
        for (date, events) in grouped {
            print("   - \(date): \(events.count) events")
        }
        return grouped
    }

    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    // MARK: - Data Loading

    private func loadEvents() async {
        isLoading = true

        do {
            let snapshot = try await db.collection("Events")
                .whereField("eventType", isEqualTo: "hosted_trivia")
                .getDocuments()

            let loadedEvents = snapshot.documents.compactMap { doc -> CalendarEvent? in
                guard let event = CalendarEvent.from(documentData: doc.data(), documentId: doc.documentID) else {
                    return nil
                }
                // Filter by status in code to avoid needing a composite index
                return (event.status == .scheduled || event.status == .active) ? event : nil
            }.sorted { $0.startTime < $1.startTime }

            await MainActor.run {
                events = loadedEvents
                isLoading = false
                print("📅 [Events] Loaded \(loadedEvents.count) trivia events")
                if loadedEvents.isEmpty {
                    print("⚠️ [Events] No events found. Check if test data was created correctly.")
                } else {
                    print("✅ [Events] Displaying \(loadedEvents.count) events")
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
            print("❌ [Events] Failed to load events: \(error)")
            print("Error details: \(error.localizedDescription)")
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

// MARK: - Preview

#if DEBUG
struct EventsCalendarView_Previews: PreviewProvider {
    static var previews: some View {
        EventsCalendarView()
    }
}
#endif
