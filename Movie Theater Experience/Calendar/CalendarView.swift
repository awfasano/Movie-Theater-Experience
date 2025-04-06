import SwiftUI
import RealityKit
import RealityKitContent

struct CalendarView: View {
    // MARK: - State
    @State private var currentDate = Date()
    @State private var refreshID = UUID()
    @State private var isRefreshing = false
    @State private var maxRow: Int = 0
    @State private var scrollToToday = false

    // MARK: - Environment
    @Environment(\.openWindow) var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(AppModel.self) private var appModel
    
    // MARK: - Observed
    @ObservedObject var calendarService: CalendarService
    
    // MARK: - Computed
    var events: [CalendarEvent] { calendarService.events }
    
    // MARK: - Layout
    let hourWidth: CGFloat = 200
    let eventHeight: CGFloat = 150
    let verticalSpacing: CGFloat = 10
    let timeLabelHeight: CGFloat = 40
    let dividerHeight: CGFloat = 1
    let topPadding: CGFloat = 5
    let minimumRows: CGFloat = 2
    
    var totalEventAreaHeight: CGFloat {
        let numberOfRows = max(CGFloat(maxRow + 1), minimumRows)
        return timeLabelHeight + dividerHeight + topPadding + numberOfRows * (eventHeight + verticalSpacing)
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                // 1) Top navigation
                TopNavigationView(
                    currentDate: $currentDate,
                    isRefreshing: $isRefreshing,
                    onRefresh: refreshCalendar,
                    onMonthScroll: scrollMonth
                )
                
                // 2) Day selection
                DaySelectionView(
                    currentDate: $currentDate,
                    scrollToToday: $scrollToToday,
                    onDateChange: { newDate in
                        currentDate = newDate
                    }
                )
                
                Divider()
                    .padding(.horizontal)
                
                // 3) Timeline - Fixed parameter order and types
                TimelineView(
                    currentDate: $currentDate,
                    scrollToToday: $scrollToToday,
                    maxRow: $maxRow,
                    events: events,
                    appModel: appModel,
                    calendarService: calendarService,
                    hourWidth: hourWidth,
                    eventHeight: eventHeight,
                    verticalSpacing: verticalSpacing,
                    timeLabelHeight: timeLabelHeight,
                    dividerHeight: dividerHeight,
                    topPadding: topPadding,
                    minimumRows: minimumRows
                )
            }
            
            // 4) Floating "Today" button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        scrollToTodayAndCurrentTime()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar").font(.largeTitle)
                            Text("Today").font(.largeTitle)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
        }
        .id(refreshID)
    }
    
    // MARK: - Actions
    private func scrollToTodayAndCurrentTime() {
        withAnimation(.spring()) {
            currentDate = Date()
            scrollToToday = true
            
            // Reset the trigger after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                scrollToToday = false
            }
        }
    }
    
    private func refreshCalendar() {
        withAnimation { isRefreshing = true }
        calendarService.events = []
        calendarService.fetchAllEvents()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                isRefreshing = false
                refreshID = UUID()
            }
        }
    }
    
    private func scrollMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentDate) {
            withAnimation {
                currentDate = newDate
            }
        }
    }
}

