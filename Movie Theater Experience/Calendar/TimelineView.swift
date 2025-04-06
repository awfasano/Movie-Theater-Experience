import SwiftUI
import RealityKit

// MARK: - Supporting Types
struct TimeSlot: Identifiable, Hashable {
    let id: String
    var time: String
    
    init(time: String) {
        self.time = time
        self.id = time
    }
}

struct PositionedEvent: Identifiable {
    let id = UUID()
    var event: CalendarEvent
    var row: Int
    var xPosition: CGFloat
    var width: CGFloat
}

struct TimelineView: View {
    // MARK: - Environment
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    // MARK: - Bindings
    @Binding var currentDate: Date
    @Binding var scrollToToday: Bool
    @Binding var maxRow: Int
    
    // MARK: - Properties
    let events: [CalendarEvent]
    let appModel: AppModel
    let calendarService: CalendarService
    
    // MARK: - Layout Constants
    let hourWidth: CGFloat
    let eventHeight: CGFloat
    let verticalSpacing: CGFloat
    let timeLabelHeight: CGFloat
    let dividerHeight: CGFloat
    let topPadding: CGFloat
    let minimumRows: CGFloat
    
    // MARK: - Time Update Timer
    @State private var currentTimeTimer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()
    
    // MARK: - Body
    var body: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // 1) Background & Time Labels
                    timeLabelsBackground
                    
                    // 2) Events Layer
                    eventsLayer
                    
                    // 3) Current Time Line (if today)
                    if Calendar.current.isDateInToday(currentDate) {
                        CurrentTimeLineView(
                            lineHeight: eventAreaHeight,
                            xPosition: calculateCurrentTimePosition()
                        )
                        .offset(y: timeLabelHeight + dividerHeight + topPadding)
                        .zIndex(100)
                    }
                }
                .frame(
                    width: hourWidth * CGFloat(timeSlots.count),
                    height: totalEventAreaHeight
                )
            }
            // Scroll Handling
            .onChange(of: scrollToToday) { newValue in
                if newValue {
                    scrollToCurrentTime(proxy: scrollViewProxy, animated: true)
                }
            }
            .onAppear {
                scrollToCurrentTime(proxy: scrollViewProxy, animated: false)
            }
            // Update current time line position
            .onReceive(currentTimeTimer) { _ in
                withAnimation(.linear(duration: 0.5)) {
                    if Calendar.current.isDateInToday(currentDate) {
                        scrollToCurrentTime(proxy: scrollViewProxy, animated: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Background Layer
    private var timeLabelsBackground: some View {
        VStack(spacing: 0) {
            // Time labels row
            HStack(spacing: 0) {
                ForEach(timeSlots) { slot in
                    Text(slot.time)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: hourWidth, height: timeLabelHeight)
                        .id(slot.id)
                }
            }
            .frame(height: timeLabelHeight)
            
            // Divider line
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: dividerHeight)
            
            Spacer()
        }
        .frame(
            width: hourWidth * CGFloat(timeSlots.count),
            height: totalEventAreaHeight
        )
    }
    
    // MARK: - Events Layer
    private var eventsLayer: some View {
        ForEach(positionedEvents()) { positionedEvent in
            EventView(event: positionedEvent.event)
                .frame(width: positionedEvent.width, height: eventHeight)
                .position(
                    x: positionedEvent.xPosition + positionedEvent.width / 2,
                    y: timeLabelHeight + dividerHeight + topPadding +
                    (CGFloat(positionedEvent.row) * (eventHeight + verticalSpacing)) +
                    eventHeight / 2
                )
                .onTapGesture {
                    openImmersiveSpaceForEvent(event: positionedEvent.event)
                }
        }
    }
    
    // MARK: - Event Positioning
    private func positionedEvents() -> [PositionedEvent] {
        var positioned: [PositionedEvent] = []
        var rows: [[CalendarEvent]] = []
        var localMaxRow = 0
        
        let dayEvents = events.filter {
            Calendar.current.isDate($0.date, inSameDayAs: currentDate)
        }
        
        for event in dayEvents.sorted(by: { $0.date < $1.date }) {
            let startHour = hourValue(for: event.date)
            let endHour = hourValue(for: event.end)
            let eventWidth = max((endHour - startHour) * hourWidth, hourWidth/2)
            let xPosition = startHour * hourWidth
            
            var placed = false
            for (index, row) in rows.enumerated() {
                if !row.contains(where: { overlapping($0, event) }) {
                    rows[index].append(event)
                    positioned.append(PositionedEvent(
                        event: event,
                        row: index,
                        xPosition: xPosition,
                        width: eventWidth
                    ))
                    placed = true
                    break
                }
            }
            
            if !placed {
                rows.append([event])
                let rowIndex = rows.count - 1
                positioned.append(PositionedEvent(
                    event: event,
                    row: rowIndex,
                    xPosition: xPosition,
                    width: eventWidth
                ))
                localMaxRow = max(localMaxRow, rowIndex)
            }
        }
        
        // Update maxRow in parent
        DispatchQueue.main.async {
            maxRow = localMaxRow
        }
        
        return positioned
    }
    
    // MARK: - Time Calculations
    private func calculateCurrentTimePosition() -> CGFloat {
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = CGFloat(components.hour ?? 0)
        let minute = CGFloat(components.minute ?? 0)
        return (hour + minute / 60) * hourWidth
    }
    
    private func hourValue(for date: Date) -> CGFloat {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hr = CGFloat(comps.hour ?? 0)
        let min = CGFloat(comps.minute ?? 0)
        return hr + min/60
    }
    
    private func overlapping(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        max(a.date, b.date) < min(a.end, b.end)
    }
    
    // MARK: - Scrolling
    private func scrollToCurrentTime(proxy: ScrollViewProxy, animated: Bool = true) {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let targetHour = max(0, currentHour - 1) // Show one hour before current time
        let targetTime = String(format: "%02d:00", targetHour)
        
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(targetTime, anchor: .leading)
            }
        } else {
            proxy.scrollTo(targetTime, anchor: .leading)
        }
    }
    
    // MARK: - Layout Calculations
    private var eventAreaHeight: CGFloat {
        let numberOfRows = max(CGFloat(maxRow + 1), minimumRows)
        return numberOfRows * (eventHeight + verticalSpacing)
    }
    
    private var totalEventAreaHeight: CGFloat {
        timeLabelHeight + dividerHeight + topPadding + eventAreaHeight
    }
    
    private var timeSlots: [TimeSlot] {
        Array(0..<24).map { hour in
            TimeSlot(time: String(format: "%02d:00", hour))
        }
    }
    
    // MARK: - Immersive Space
    private func openImmersiveSpaceForEvent(event: CalendarEvent) {
        Task { @MainActor in
            appModel.selectedVideoURL = event.videoURLObject
            appModel.currentEvent = event
            
            guard await ImmersiveSpaceManager.shared.prepareForOpening() else {
                print("❌ Failed to prepare space for opening")
                return
            }
            
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                print("✅ Space opened successfully")
                ImmersiveSpaceManager.shared.handleOpenSuccess()
                
            case .userCancelled, .error:
                fallthrough
            @unknown default:
                print("❌ Failed to open space")
                ImmersiveSpaceManager.shared.handleOpenFailure()
                appModel.selectedVideoURL = nil
                appModel.currentEvent = nil
            }
        }
    }
}
