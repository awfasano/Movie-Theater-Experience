import Foundation
import SwiftUI
import RealityKit

struct TabBarWindow: View {
    // This state controls which tab is currently active.
    @State private var selectedTab: Int = 0
    
    // A local state object for this window's specific needs.
    //@StateObject private var calendarService = CalendarService()
    
    // MARK: - Environment Objects
    // These objects are inherited from the parent view (now the App struct).
    // They are available to this view and all of its children automatically.
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var selectedSpace: SelectedSpace
    @EnvironmentObject private var windowManager: WindowManager
    @EnvironmentObject private var spaceManager: ImmersiveSpaceManager
    @EnvironmentObject private var sharedSelection: SharedSeatSelection
    
    // Add dismissWindow environment action for cleanup
    @Environment(\.dismissWindow) private var dismissWindowAction
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // --- Welcome Tab ---
            Group {
                WelcomeView(selectedTab: $selectedTab)
                // Note: No .environmentObject modifiers are needed here.
                // WelcomeView will automatically inherit them from TabBarWindow.
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // --- Spaces Tab ---
            Group {
                SpaceBrowserIntegration()
                // Child views of SpaceBrowserIntegration will also inherit the environment objects.
            }
            .tabItem { Label("Spaces", systemImage: "cube.fill") }
            .tag(1)

            // --- Events Tab ---
            Group {
                EventsCalendarView()
                    .environmentObject(HostedEventManager.shared)
            }
            .tabItem { Label("Events", systemImage: "calendar") }
            .tag(2)

            // --- Settings Tab ---
            Group {
                ChatSettingsWindow()
            }
            .tabItem { Label("Chat Settings", systemImage: "gear") }
            .tag(3)
        }
        .onAppear {
            // When TabBar appears, ensure all space windows are closed
            cleanupSpaceWindows()
        }
    }
    
    /// Cleans up any lingering space windows when the TabBar appears
      /// This handles cases where windows fail to close during Digital Crown dismissal
      private func cleanupSpaceWindows() {
          // Check if NavBar is still open and force close it
          if windowManager.isWindowOpen(.spaceNavBar) {
              print("🧹 [TabBar] NavBar still open after space dismissal - force closing")
              dismissWindowAction(id: WindowType.spaceNavBar.rawValue)
              windowManager.untrackWindow(.spaceNavBar)
          }
          
          // Clean up any other space windows that might be lingering
          for windowType in windowManager.spaceWindowTypes {
              if windowManager.isWindowOpen(windowType) {
                  print("🧹 [TabBar] Closing lingering space window: \(windowType.rawValue)")
                  dismissWindowAction(id: windowType.rawValue)
                  windowManager.untrackWindow(windowType)
              }
          }
          
          // Also check for any browser windows
          if windowManager.browserWindowCount > 0 {
              print("🧹 [TabBar] Closing \(windowManager.browserWindowCount) browser windows")
              windowManager.closeAllWebBrowsers(dismissAction: dismissWindowAction)
          }
          
          // Final cleanup log
          if windowManager.activeWindows.count > 1 { // More than just mainContent
              print("⚠️ [TabBar] Still tracking windows after cleanup: \(windowManager.activeWindows)")
          } else {
              print("✅ [TabBar] All space windows successfully cleaned up")
          }
      }
  }
