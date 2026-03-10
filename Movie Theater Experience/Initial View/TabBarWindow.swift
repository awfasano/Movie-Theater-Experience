import Foundation
import SwiftUI

struct TabBarWindow: View {
    private enum Tab: Int {
        case showings = 0
        case spaces = 1
        case settings = 2
        case setup = 3
    }

    @State private var selectedTab: Tab = .showings
    @StateObject private var calendarService = CalendarService()
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var windowManager: WindowManager
    @EnvironmentObject private var spaceManager: ImmersiveSpaceManager

    var body: some View {
        TabView(selection: $selectedTab) {
            // CalendarView Tab
            CalendarView(calendarService: calendarService)
                .tabItem {
                    Label("Current Showings", systemImage: "calendar")
                }
                .tag(Tab.showings)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            // Space Browser Tab - Updated to use SpaceBrowserIntegration
            SpaceBrowserIntegration()
                .tabItem {
                    Label("Spaces", systemImage: "cube.fill")
                }
                .tag(Tab.spaces)

            // Chat Settings Tab
            ChatSettingsWindow()
                .tabItem {
                    Label("Chat Settings", systemImage: "gear")
                }
                .tag(Tab.settings)

            // Admin/Setup Tab (for seeding ambient spaces)
            AmbientSetupView()
                .tabItem {
                    Label("Setup", systemImage: "wrench.and.screwdriver")
                }
                .tag(Tab.setup)
        }
        .onAppear {
            calendarService.fetchAllEvents()
        }
    }
}
