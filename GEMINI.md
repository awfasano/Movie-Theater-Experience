Step 1: Update the WindowManager
The most robust approach is to have the WindowManager coordinate the actions directly, rather than just tracking state. This avoids potential issues where the tracked state (activeWindows) gets out of sync with the actual UI.

Replace your current WindowManager code with this enhanced version. It uses your WindowType enum but focuses on coordinating actions.

// WindowManager.swift
import SwiftUI

// Your WindowType enum is great, let's keep it!
enum WindowType: String, CaseIterable {
    // ... (keep all your cases here) ...
    case chat = "chatWindow"
    case emoji = "emojiWindow"
    case movie = "movieWindow"
    case seatMap = "seatMap"
    case chatSettings = "chatSettings"
    case exitingWindow = "exitingWindow"
    case navBar = "navBar"
    case spaceNavBar = "spaceNavBar"
    case spaceMap = "spaceMap"
    case spaceChatWindow = "spaceChatWindow"
    case spaceEmojiWindow = "spaceEmojiWindow"
    case audioControls = "audioControls"
    case storytellerWindow = "storytellerWindow"
    case userListWindow = "userListWindow"
    case webBrowserWindow = "webBrowserWindow"
    case movementControl = "movementControl"
}

@MainActor
class WindowManager: ObservableObject {
    // This array defines all windows that belong to the "Spaces" experience.
    // The manager will use this list to know what to close.
    let spaceWindowTypes: [WindowType] = [
        .spaceNavBar,
        .spaceMap,
        .spaceChatWindow,
        .spaceEmojiWindow,
        .audioControls,
        .storytellerWindow,
        .userListWindow,
        .webBrowserWindow,
        .movementControl
    ]
    
    // The enum case for your main window that you want to return to.
    let mainWindowType: WindowType = .chatSettings // As an example, assuming TabBar is in ChatSettings

    // This method will be called when entering the immersive space.
    func openSpaceEntryWindows(openWindow: OpenWindowAction) {
        print("🪟 [WindowManager] Opening space entry windows...")
        openWindow(id: WindowType.spaceNavBar.rawValue)
        openWindow(id: WindowType.spaceChatWindow.rawValue)
    }

    // This method will be called when exiting the immersive space.
    func closeAllSpaceWindows(dismissWindow: DismissWindowAction) {
        print("🪟 [WindowManager] Closing all space-related windows...")
        for windowType in spaceWindowTypes {
            dismissWindow(id: windowType.rawValue)
        }
    }
    
    // This method opens the main application window after the space is closed.
    func openMainWindow(openWindow: OpenWindowAction) {
        print("🪟 [WindowManager] Opening main window...")
        // We need a main window to open. Your TabBar is inside the "mainContent" WindowGroup.
        // Let's assume you have a main window ID.
        openWindow(id: "mainContent")
    }
}
Step 2: Update Your Main App File
In Movie_Theater_ExperienceApp.swift, ensure you instantiate the WindowManager and inject it into the environment for the scenes that need it. The window IDs must match the .rawValue of your WindowType enum.

// Movie_Theater_ExperienceApp.swift
import SwiftUI

@main
struct Movie_Theater_ExperienceApp: App {
    
    // Instantiate your WindowManager
    @StateObject private var windowManager = WindowManager()
    
    var body: some Scene {
        // Main content window (this is what will reopen)
        WindowGroup(id: "mainContent") {
            ContentView()
                .environmentObject(windowManager)
        }
        
        // Immersive space for Spaces
        ImmersiveSpace(id: appModel.spacesID) {
            SpacesView()
                .environmentObject(windowManager)
        }
        
        // Ensure all your WindowGroups use the .rawValue from the enum for their ID
        
        // Example: Space Nav Bar window
        WindowGroup("Space Nav Bar", id: WindowType.spaceNavBar.rawValue) {
            SpacesNavBarView()
                .environmentObject(windowManager)
        }
        
        // Example: Space Chat window
        WindowGroup(id: WindowType.spaceChatWindow.rawValue) {
            SpacesChatWindow()
                .environmentObject(windowManager)
        }

        // ... and so on for all other WindowGroups ...
        // Make sure to remove the .onDisappear { windowManager.windowClosed(...) }
        // calls from your WindowGroup views, as they are no longer needed.
    }
}
Step 3: Modify SpacesView.swift
Now, update SpacesView to call the WindowManager's new methods when the view appears and disappears.

// SpacesView.swift
import SwiftUI

struct SpacesView: View {
    // Environment
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowManager: WindowManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        ZStack {
            // Your existing view content
        }
        .task {
            print("📱 SpacesView appeared")
            await initializeSpace()
        }
        .onDisappear {
            // This robustly handles the exit sequence
            cleanupView()
        }
    }

    // Core Functionality
    @MainActor
    private func initializeSpace() async {
        // Use the manager to open the correct windows on entry
        windowManager.openSpaceEntryWindows(openWindow: openWindow)
        
        // ... rest of your initializeSpace function ...
    }
    
    private func cleanupView() {
        // Use the manager to perform the full exit sequence
        windowManager.closeAllSpaceWindows(dismissWindow: dismissWindow)
        windowManager.openMainWindow(openWindow: openWindow)

        // Reset any other necessary app state
        appModel.selectedSpace = nil
        appModel.currentActiveSpace = nil
    }
}
Step 4: Simplify SpacesNavBarView.swift
Finally, simplify the exit button in SpacesNavBarView. Its only job is to dismiss the immersive space. The onDisappear trigger you just added to SpacesView will handle the rest of the cleanup automatically.

// SpacesNavBarView.swift
import SwiftUI

struct SpacesNavBarView: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @EnvironmentObject private var windowManager: WindowManager

    var body: some View {
        HStack {
            // The exit button action is now very simple
            Button(action: {
                Task {
                    // Just dismiss the space. The cleanupView() in SpacesView
                    // will handle closing all windows and opening the main one.
                    await dismissImmersiveSpace()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .help("Exit immersive space")

            // ... rest of your nav bar buttons
        }
    }
}