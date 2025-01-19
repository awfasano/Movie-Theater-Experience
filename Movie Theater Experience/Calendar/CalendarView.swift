import SwiftUI

struct CalendarView: View {
    @State private var currentDate = Date()
    @Environment(\.openWindow) var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(AppModel.self) private var appModel

    let events: [CalendarEvent]

    // Constants for layout
    let hourWidth: CGFloat = 200       // Width of each hour slot
    let eventHeight: CGFloat = 150     // Height of each event
    let verticalSpacing: CGFloat = 10  // Spacing between event rows
    let timeLabelHeight: CGFloat = 40  // Height of the time labels
    let dividerHeight: CGFloat = 1     // Height of the divider line
    let topPadding: CGFloat = 5        // Additional padding between time labels and events
    let minimumRows: CGFloat = 2       // Minimum number of rows to display

    // TimeSlot struct for time labels
    struct TimeSlot: Identifiable {
        var id: String { time }
        var time: String
    }

    // Generate times array with TimeSlot objects
    let times = Array(0..<24).map { hour -> TimeSlot in
        TimeSlot(time: String(format: "%02d:00", hour))
    }

    var body: some View {
        VStack {
            // Month and Day Bar with scrolling
            HStack {
                Button(action: {
                    scrollMonth(by: -1)
                }) {
                    Image(systemName: "chevron.left")
                }
                Text(currentDate.monthAndYear)
                    .font(.title2)
                    .bold()
                Button(action: {
                    scrollMonth(by: 1)
                }) {
                    Image(systemName: "chevron.right")
                }
                Spacer()
            }
            .padding(.horizontal)

            // Scrollable Month Day Grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(currentDate.startOfMonth.daysInMonth(), id: \.self) { day in
                        VStack {
                            Text(day.weekdaySymbol)
                                .font(.body)
                            Text("\(day.day)")
                                .font(.largeTitle)
                                .foregroundColor(textColor(for: day))
                                .padding(20)
                                .background(
                                    ZStack {
                                        if isToday(day: day) {
                                            Circle().fill(Color.red)
                                        } else if isSelected(day: day) {
                                            Circle().fill(Color(UIColor.systemGray5))
                                        }
                                    }
                                )
                        }
                        .onTapGesture {
                            currentDate = day
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
            }

            // Divider
            Divider()

            // Time slots in a horizontal scrollable view with events
            ScrollViewReader { scrollViewProxy in
                ScrollView(.horizontal) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            // Time labels
                            HStack(spacing: 0) {
                                ForEach(times) { timeSlot in
                                    Text(timeSlot.time)
                                        .font(.body)
                                        .frame(width: hourWidth, height: timeLabelHeight)
                                        .id(timeSlot.id) // Assign ID here
                                }
                            }
                            .frame(height: timeLabelHeight)

                            // Divider
                            Rectangle()
                                .fill(Color.gray)
                                .frame(height: dividerHeight)

                            Spacer()
                        }
                        .frame(width: hourWidth * CGFloat(times.count), height: totalEventAreaHeight)

                        // Events
                        ForEach(positionedEvents(), id: \.event.id) { positionedEvent in
                            EventView(event: positionedEvent.event)
                                .frame(width: positionedEvent.width, height: eventHeight)
                                .position(
                                    x: positionedEvent.xPosition + positionedEvent.width / 2,
                                    y: timeLabelHeight + dividerHeight + topPadding + (CGFloat(positionedEvent.row) * (eventHeight + verticalSpacing)) + eventHeight / 2
                                )
                                .onTapGesture {
                                    openImmersiveSpaceForEvent(event: positionedEvent.event)
                                }
                        }

                        // Current Time Line
                        currentTimeLine()
                            .offset(y: timeLabelHeight + dividerHeight + topPadding)
                    }
                }
                .frame(width: 6 * hourWidth, height: totalEventAreaHeight)
                .onAppear {
                    let currentHour = Calendar.current.component(.hour, from: Date())
                    let targetHour = max(0, currentHour - 1) // One hour before current time
                    let targetTime = String(format: "%02d:00", targetHour)
                    scrollViewProxy.scrollTo(targetTime, anchor: .leading)
                }
            }
        }
    }

    // MARK: - Helper Functions

    // Calculate total height of the event area based on number of rows
    var totalEventAreaHeight: CGFloat {
        let numberOfRows = max(CGFloat(maxRow + 1), minimumRows)
        return timeLabelHeight + dividerHeight + topPadding + numberOfRows * (eventHeight + verticalSpacing)
    }

    @State private var maxRow: Int = 0

    // Check if the current day is today
    func isToday(day: Date) -> Bool {
        Calendar.current.isDateInToday(day)
    }

    // Check if the day is the currently selected day
    func isSelected(day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: currentDate)
    }

    // Scroll the calendar by months
    func scrollMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentDate) {
            currentDate = newDate
        }
    }

    func openImmersiveSpaceForEvent(event: CalendarEvent) {
        Task { @MainActor in
            appModel.selectedVideoURL = event.videoURLObject
            appModel.currentEvent = event  // Make sure this line exists
            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                case .opened:
                    appModel.immersiveSpaceState = .open
                    // Open the navigation bar
                    openWindow(id: "navBar")
                case .userCancelled, .error:
                    appModel.immersiveSpaceState = .closed
                @unknown default:
                    appModel.immersiveSpaceState = .closed
            }
        }
    }
    // Calculate positioned events to handle overlapping
    func positionedEvents() -> [PositionedEvent] {
        var positionedEvents: [PositionedEvent] = []
        var rows: [[CalendarEvent]] = []
        var localMaxRow = 0

        // Filter events for the selected day
        let dayEvents = events.filter { Calendar.current.isDate($0.date, inSameDayAs: currentDate) }

        for event in dayEvents {
            let startComponents = Calendar.current.dateComponents([.hour, .minute], from: event.date)
            let endComponents = Calendar.current.dateComponents([.hour, .minute], from: event.end)
            let startHour = CGFloat(startComponents.hour ?? 0) + CGFloat(startComponents.minute ?? 0) / 60
            let endHour = CGFloat(endComponents.hour ?? 0) + CGFloat(endComponents.minute ?? 0) / 60
            let eventWidth = (endHour - startHour) * hourWidth
            let xPosition = startHour * hourWidth

            var placed = false
            for (index, row) in rows.enumerated() {
                if !row.contains(where: { overlapping(event1: $0, event2: event) }) {
                    rows[index].append(event)
                    positionedEvents.append(PositionedEvent(event: event, row: index, xPosition: xPosition, width: eventWidth))
                    placed = true
                    break
                }
            }
            if !placed {
                rows.append([event])
                let rowIndex = rows.count - 1
                positionedEvents.append(PositionedEvent(event: event, row: rowIndex, xPosition: xPosition, width: eventWidth))
                localMaxRow = max(localMaxRow, rowIndex)
            }
        }

        // Update maxRow state
        DispatchQueue.main.async {
            self.maxRow = localMaxRow
        }

        return positionedEvents
    }

    // Check if two events overlap
    func overlapping(event1: CalendarEvent, event2: CalendarEvent) -> Bool {
        return max(event1.date, event2.date) < min(event1.end, event2.end)
    }

    // Line for the current time indicator
    func currentTimeLine() -> some View {
        GeometryReader { geometry in
            let currentTimePosition = calculateCurrentTimePosition()
            Path { path in
                path.move(to: CGPoint(x: currentTimePosition, y: 0))
                path.addLine(to: CGPoint(x: currentTimePosition, y: geometry.size.height))
            }
            .stroke(Color.red, lineWidth: 2)
        }
        .frame(height: eventAreaHeight)
    }

    // Height of the event area without time labels and spacing
    var eventAreaHeight: CGFloat {
        let numberOfRows = max(CGFloat(maxRow + 1), minimumRows)
        return numberOfRows * (eventHeight + verticalSpacing)
    }

    // Calculate the current time's position within the scrollable area
    func calculateCurrentTimePosition() -> CGFloat {
        let currentDateTime = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: currentDateTime)
        let hour = CGFloat(components.hour ?? 0)
        let minute = CGFloat(components.minute ?? 0)
        return (hour + minute / 60) * hourWidth
    }

    // Helper function to determine text color
    func textColor(for day: Date) -> Color {
        if isToday(day: day) {
            return .white
        } else if isSelected(day: day) {
            return .primary
        } else {
            return .primary
        }
    }
}

// Helper struct for positioned events
struct PositionedEvent {
    var event: CalendarEvent
    var row: Int
    var xPosition: CGFloat
    var width: CGFloat
}
