import SwiftUI

struct CalendarView: View {
    @State private var currentDate = Date()
    let events: [CalendarEvent]
    let times = Array(0..<24).map { String(format: "%02d:00", $0) }
    
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
                                .foregroundColor(isToday(day: day) ? .white : .primary)
                                .padding(20)
                                .background(isToday(day: day) ? Circle().fill(Color.red) : nil)
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

            // Time slots in a horizontal scrollable view with six hours visible
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(times, id: \.self) { time in
                            VStack {
                                Text(time)
                                    .font(.body)
                                    .frame(width: 120)
                                    .padding(.bottom, 5)

                                Divider()

                                // Stack events vertically based on time
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(eventsThatStart(at: time), id: \.id) { event in
                                        EventView(event: event)
                                            .frame(width: eventWidth(for: event), height: 60)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(8)
                                    }
                                }
                                .frame(width: 120, height: 60)

                                Spacer()
                            }
                        }
                    }
                }
                .frame(height: 360) // Height for 6 hours
                .overlay(currentTimeLine(), alignment: .topLeading) // Line for current time
            }
        }
    }

    // Check if the current day is today
    func isToday(day: Date) -> Bool {
        Calendar.current.isDateInToday(day)
    }

    // Scroll the calendar by months
    func scrollMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentDate) {
            currentDate = newDate
        }
    }

    // Get events that start at the specific time
    func eventsThatStart(at time: String) -> [CalendarEvent] {
        events.filter { event in
            event.date.hourAndMinute == time
        }
    }

    // Calculate the width of the event based on its duration
    func eventWidth(for event: CalendarEvent) -> CGFloat {
        let durationInHours = event.end.timeIntervalSince(event.date) / 3600
        let hourWidth: CGFloat = 120 // Each hour takes 120 points width
        return CGFloat(durationInHours) * hourWidth
    }

    // Line for the current time indicator
    func currentTimeLine() -> some View {
        GeometryReader { geometry in
            let currentTimePosition = calculateCurrentTimePosition(geometry.size.width)
            Path { path in
                path.move(to: CGPoint(x: currentTimePosition, y: 0))
                path.addLine(to: CGPoint(x: currentTimePosition, y: geometry.size.height))
            }
            .stroke(Color.red, lineWidth: 2)
        }
        .frame(height: 360)
    }

    // Calculate the current time's position within the scrollable area
    func calculateCurrentTimePosition(_ width: CGFloat) -> CGFloat {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let hourWidth = width / CGFloat(times.count)
        return CGFloat(currentHour) * hourWidth
    }
}

// Calendar extensions for Date handling
extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))!
    }

    var monthAndYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: self)
    }

    var weekdaySymbol: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: self)
    }

    var day: Int {
        Calendar.current.component(.day, from: self)
    }

    var hourAndMinute: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    func daysInMonth() -> [Date] {
        let range = Calendar.current.range(of: .day, in: .month, for: self)!
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return range.compactMap { day -> Date? in
            var dateComponents = components
            dateComponents.day = day
            return Calendar.current.date(from: dateComponents)
        }
    }
}
