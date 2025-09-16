import SwiftUI

// MARK: - WindowType Enum

// Define identifiers for all your windows here.
enum WindowType: String, CaseIterable {
    // Main Application Windows
    case mainContent = "mainContent"
    //case tabBar = "mainContent"

    // Movie Theatre Experience Windows (if still used)
    case chat = "chatWindow"
    case emoji = "emojiWindow"
    case movie = "movieWindow"
    case seatMap = "seatMap"
    case navBar = "navBar" // NavBar for Movie Theatre

    // General Utility Windows
    case chatSettings = "chatSettings"
    case exitingWindow = "exitingWindow"
    case userListWindow = "userListWindow"
    case webBrowserWindow = "webBrowserWindow"

    // Spaces Experience Windows
    case spaceNavBar = "spaceNavBar"
    case spaceMap = "spaceMap"
    case spaceChatWindow = "spaceChatWindow"
    case spaceEmojiWindow = "spaceEmojiWindow"
    case audioControls = "audioControls"
    case storytellerWindow = "storytellerWindow"
    case movementControl = "movementControl"
}

// MARK: - WindowManager Class

@MainActor
class WindowManager: ObservableObject {
    // Track which windows are currently active
    @Published var activeWindows: Set<String> = []
    
    // This array defines all windows that belong to the "Spaces" experience
    let spaceWindowTypes: [WindowType] = [
        .spaceNavBar, .spaceMap, .spaceChatWindow, .spaceEmojiWindow,
        .audioControls, .storytellerWindow, .userListWindow,
        .webBrowserWindow, .movementControl
    ]
    
    // The enum case for your main window that you want to return to
    let mainWindowType: WindowType = .mainContent
    
    // MARK: - Tracking Methods (Used by WindowTrackingModifier)

    /// Called by WindowTrackingModifier onAppear
    func trackWindow(_ windowType: WindowType) {
        if activeWindows.insert(windowType.rawValue).inserted {
            print("✅ [WindowManager] Tracked window: \(windowType.rawValue)")
        }
    }

    /// Called by WindowTrackingModifier when scenePhase goes to background
    /// Called by WindowTrackingModifier when scenePhase goes to background
    // ✅ FIXED: This is now back to its simple, original version.
    // It is safe for other functions like openMainWindow to call this.
    func untrackWindow(_ windowType: WindowType) {
        if activeWindows.remove(windowType.rawValue) != nil {
            print("✅ [WindowManager] Untracked window: \(windowType.rawValue)")
        }
    }
    
    // MARK: - Space Entry/Exit Methods
    
    /// Called when entering the immersive space (e.g., from SpacesView.initializeSpace)
    // FIX: Renamed parameters to openAction and dismissAction to avoid ambiguity
    func openSpaceEntryWindows(openAction: OpenWindowAction, dismissAction: DismissWindowAction) {
        print("🪟 [WindowManager] Opening space entry windows...")
        
        // First, dismiss the tab bar if it's open
        if isWindowOpen(.mainContent) {
            closeWindow(.mainContent, dismissAction: dismissAction)
        }
        
        // Then open the space nav bar.
        // This uses the helper openWindow which checks for duplicates.
        openWindow(.spaceNavBar, openAction: openAction)
    }
    
    /// Called when exiting the immersive space (e.g., from SpacesView.cleanupView)
    // FIX: Renamed parameter to dismissAction
    func closeAllSpaceWindows(dismissAction: DismissWindowAction) {
        print("🪟 [WindowManager] Closing all space-related windows...")
        
        // Close all space-specific windows
        for windowType in spaceWindowTypes {
            closeWindow(windowType, dismissAction: dismissAction)
        }
        
        // Also close chat settings if it's open (it might be opened from spaces)
        closeWindow(.chatSettings, dismissAction: dismissAction)

        // Close any movie theatre windows that might still be open (just in case)
        let movieWindows: [WindowType] = [.chat, .emoji, .movie, .navBar, .seatMap]
        for windowType in movieWindows {
            closeWindow(windowType, dismissAction: dismissAction)
        }
        
        print("✅ [WindowManager] All space windows closed attempt complete.")
    }
    
    // ✅ NEW: A new function specifically for handling the scenePhase change.
    // This function contains the special logic for the nav bar.
    func handleWindowClosure(
        for windowType: WindowType,
        openWindowAction: OpenWindowAction
    ) {
        // First, perform the basic untrack action.
        untrackWindow(windowType)
        
        // Then, check if we need to perform a follow-up action.
        if windowType == .spaceNavBar {
            print("🚪 [WindowManager] SpaceNavBar closed, triggering main window to open.")
            openMainWindow(openAction: openWindowAction)
        }
    }
    
    
    /// Opens the main application window after the space is closed (e.g., from SpacesView.cleanupView)
    // FIX: Renamed parameter to openAction
    func openMainWindow(openAction: OpenWindowAction) {
        print("🪟 [WindowManager] Opening main window (tab bar)...")
        
        // Ensure tracking is clear for space windows just in case they didn't close properly
        for windowType in spaceWindowTypes {
            untrackWindow(windowType)
        }
        
        // Open the tab bar window (handles duplicate check internally)
        openWindow(.mainContent, openAction: openAction)
    }
    
    // MARK: - Emergency Exit Method (for when immersive space fails to load content)
    
    /// Performs emergency cleanup when immersive space has no content
    // FIX: Renamed parameters
    func performEmergencyExit(
        dismissAction: DismissWindowAction,
        openAction: OpenWindowAction,
        dismissImmersiveSpace: @escaping () async -> Void
    ) async {
        print("🚨 [WindowManager] Performing emergency exit from empty immersive space")
        
        // Step 1: Close all space windows
        closeAllSpaceWindows(dismissAction: dismissAction)
        
        // Step 2: Small delay to ensure windows close
        try? await Task.sleep(for: .milliseconds(100))
        
        // Step 3: Dismiss the immersive space
        await dismissImmersiveSpace()
        
        // Step 4: Wait a moment for the immersive space to fully dismiss
        try? await Task.sleep(for: .milliseconds(200))
        
        // Step 5: Open the tab bar
        openMainWindow(openAction: openAction)
        
        print("✅ [WindowManager] Emergency exit complete")
    }
    
    // MARK: - Helper Methods
    
    /// Check if we're currently in a space experience
    var isInSpaceExperience: Bool {
        !activeWindows.intersection(spaceWindowTypes.map { $0.rawValue }).isEmpty
    }
    
    /// Check if a specific window is open
    func isWindowOpen(_ windowType: WindowType) -> Bool {
        activeWindows.contains(windowType.rawValue)
    }
    
    /// Open a specific window. Tracking happens automatically via the modifier.
    // FIX: Renamed parameter to openAction
    func openWindow(_ windowType: WindowType, openAction: OpenWindowAction) {
        // Check if already open to prevent duplicates.
        guard !isWindowOpen(windowType) else {
            print("⚠️ [WindowManager] Window \(windowType.rawValue) already open, ignoring request.")
            return
        }
        
        print("🚀 [WindowManager] Requesting openWindow(\(windowType.rawValue))")
        // Request the system to open the window.
        openAction(id: windowType.rawValue)
        // Note: We don't insert into activeWindows here; the WindowTrackingModifier does it onAppear.
    }
    
    /// Close a specific window. Untracking happens automatically via the modifier.
    // FIX: Renamed parameter to dismissAction
    func closeWindow(_ windowType: WindowType, dismissAction: DismissWindowAction) {
        // Only attempt to dismiss if we currently track it as open.
        guard isWindowOpen(windowType) else { return }

        print("🚪 [WindowManager] Requesting dismissWindow(\(windowType.rawValue))")
        // Request the system to close the window.
        dismissAction(id: windowType.rawValue)
        // Note: We don't remove from activeWindows here; the WindowTrackingModifier does it when scenePhase changes.
    }
}


struct WindowTrackingModifier: ViewModifier {
    @EnvironmentObject var windowManager: WindowManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindowAction
    
    let windowType: WindowType

    // This is inside the WindowTrackingModifier struct

    func body(content: Content) -> some View {
        content
            .onAppear {
                Task { @MainActor in
                    windowManager.trackWindow(windowType)
                }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background {
                    print("🪟 [WindowTracker] Window \(windowType.rawValue) phase moved to background (closed).")
                    Task { @MainActor in
                        // ✅ FIXED: Call the new, specific function for this job.
                        windowManager.handleWindowClosure(
                            for: windowType,
                            openWindowAction: openWindowAction
                        )
                    }
                }
            }
    }
}

// MARK: - View Extension
extension View {
    func trackWindow(type: WindowType) -> some View {
        self.modifier(WindowTrackingModifier(windowType: type))
    }
}
