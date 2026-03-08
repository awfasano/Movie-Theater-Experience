import Foundation
import SwiftUI

struct TabBarWindow: View {
    @State private var selectedTab: Int = 0
    @StateObject private var calendarService = CalendarService()
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var selectedSpace: SelectedSpace
    @EnvironmentObject private var windowManager: WindowManager
    @EnvironmentObject private var spaceManager: ImmersiveSpaceManager
    @EnvironmentObject private var theatreEntityWrapper: TheatreEntityWrapper
    @EnvironmentObject private var sharedSelection: SharedSeatSelection
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // CalendarView Tab
            CalendarView(calendarService: calendarService)
                .tabItem {
                    Label("Current Showings", systemImage: "calendar")
                }
                .tag(0)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            // Space Browser Tab - Updated to use SpaceBrowserIntegration
            SpaceBrowserIntegration()
                .tabItem {
                    Label("Spaces", systemImage: "cube.fill")
                }
                .tag(1)
            
            // Chat Settings Tab
            ChatSettingsWindow()
                .tabItem {
                    Label("Chat Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .onAppear {
            calendarService.fetchAllEvents()
        }
    }
}
