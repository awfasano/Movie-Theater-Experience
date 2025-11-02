import SwiftUI

// MARK: - WindowType Enum

// Define identifiers for all your windows here.
enum WindowType: String, CaseIterable {
    // Main Application Windows
    case mainContent = "mainContent"
    //case tabBar = "mainContent"

    // Movie Theatre Experience Windows (if still used)
    case chat = "chatWindow"


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
    case spaceDrawingWindow = "spaceDrawingWindow"
    
    // Dynamic case for multiple browser instances
    static func webBrowserInstance(_ instanceId: String) -> String {
        return "webBrowser_\(instanceId)"
    }
}

// MARK: - WindowManager Class

@MainActor
class WindowManager: ObservableObject {
    // Track which windows are currently active
    @Published var activeWindows: Set<String> = []
    
    // Track recently dismissed windows to handle reopen timing
    @Published private var recentlyDismissed: Set<String> = []
    
    // Track browser instances specifically
    @Published private var browserInstances: Set<String> = []
    @Published private var isOpeningMainWindow = false

    // NEW: Flag to manage immersive space exit sequence synchronization
    @Published private var isHandlingImmersiveExit = false

    
    // This array defines all windows that belong to the "Spaces" experience
    let spaceWindowTypes: [WindowType] = [
        .spaceNavBar, .spaceMap, .spaceChatWindow, .spaceEmojiWindow,
        .audioControls, .storytellerWindow, .userListWindow,
        .webBrowserWindow, .movementControl, .spaceDrawingWindow
    ]
    
    // The enum case for your main window that you want to return to
    let mainWindowType: WindowType = .mainContent
    
    // Computed property to get browser window count
    var browserWindowCount: Int {
        return browserInstances.count
    }
    
    // MARK: - Tracking Methods (Used by WindowTrackingModifier)

    /// Called by WindowTrackingModifier onAppear
    func trackWindow(_ windowType: WindowType) {
        if activeWindows.insert(windowType.rawValue).inserted {
            // Remove from recently dismissed when successfully tracked
            recentlyDismissed.remove(windowType.rawValue)
            print("✅ [WindowManager] Tracked window: \(windowType.rawValue)")
        }
    }
    
    /// Track browser instances with custom ID
    func trackBrowserWindow(_ instanceId: String) {
        let windowId = WindowType.webBrowserInstance(instanceId)
        if activeWindows.insert(windowId).inserted {
            browserInstances.insert(instanceId)
            recentlyDismissed.remove(windowId)
            print("✅ [WindowManager] Tracked browser window: \(windowId)")
        }
    }

    /// Called by WindowTrackingModifier when scenePhase goes to background
    func untrackWindow(_ windowType: WindowType) {
        if activeWindows.remove(windowType.rawValue) != nil {
            // Add to recently dismissed to handle reopen attempts
            recentlyDismissed.insert(windowType.rawValue)
            
            // Clear from recently dismissed after a delay
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.recentlyDismissed.remove(windowType.rawValue)
            }
            
            print("✅ [WindowManager] Untracked window: \(windowType.rawValue)")
        }
    }
    
    /// Untrack browser instances with custom ID
    func untrackBrowserWindow(_ instanceId: String) {
        let windowId = WindowType.webBrowserInstance(instanceId)
        if activeWindows.remove(windowId) != nil {
            browserInstances.remove(instanceId)
            recentlyDismissed.insert(windowId)
            
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.recentlyDismissed.remove(windowId)
            }
            
            print("✅ [WindowManager] Untracked browser window: \(windowId)")
        }
    }
    
    // MARK: - Space Entry/Exit Methods
    
    /// Called when entering the immersive space (e.g., from SpacesView.initializeSpace)
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
    // In WindowManager.swift, update the closeAllSpaceWindows method:

    func closeAllSpaceWindows(dismissAction: DismissWindowAction) {
        print("🪟 [WindowManager] Closing all space-related windows (Forced)...")
        
        // Define all window types relevant during a space exit
        var allRelevantTypes = Set(spaceWindowTypes.map { $0.rawValue })
        allRelevantTypes.insert(WindowType.chatSettings.rawValue)
        
        // Check if NavBar is the ONLY window open
        let openSpaceWindows = activeWindows.intersection(allRelevantTypes)
        let isNavBarOnly = openSpaceWindows.count == 1 &&
                           openSpaceWindows.contains(WindowType.spaceNavBar.rawValue)
        
        if isNavBarOnly {
            print("⚠️ [WindowManager] NavBar is the only window - using delayed dismissal")
            // When NavBar is alone, we need a different strategy
            untrackWindow(.spaceNavBar)
            
            // Schedule dismissal after the immersive space starts closing
            Task { @MainActor in
                // Wait for immersive space to begin dismissal
                try? await Task.sleep(for: .milliseconds(300))
                
                // Now try to dismiss the NavBar multiple times
                for attempt in 1...5 {
                    print("🔄 [WindowManager] Solo NavBar dismiss attempt \(attempt)")
                    dismissAction(id: WindowType.spaceNavBar.rawValue)
                    
                    if attempt < 5 {
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                }
            }
        } else {
            // Normal flow when other windows are present
            if activeWindows.contains(WindowType.spaceNavBar.rawValue) {
                print("🚪 [WindowManager] Force closing spaceNavBar with other windows")
                dismissAction(id: WindowType.spaceNavBar.rawValue)
                untrackWindow(.spaceNavBar)
            }
        }
        
        // Close other space windows
        let windowsToClose = activeWindows.intersection(allRelevantTypes)
        for windowId in windowsToClose {
            if let windowType = WindowType(rawValue: windowId) {
                if windowType == .spaceNavBar {
                    continue // Already handled above
                }
                closeWindow(windowType, dismissAction: dismissAction, force: true)
                
            }
        }
        
        // Close all web browser instances
        closeAllWebBrowsers(dismissAction: dismissAction)
        
        print("✅ [WindowManager] All space windows closed attempt complete.")
    }
    
    func closeWindow(_ windowType: WindowType, dismissAction: DismissWindowAction, force: Bool = false) {
        // Only attempt to dismiss if we currently track it as open, OR if we are forcing the closure.
        if !force && !isWindowOpen(windowType) {
             // If not forcing and the window isn't tracked as open, do nothing.
             return
        }

        print("🚪 [WindowManager] Requesting dismissWindow(\(windowType.rawValue)) (Forced: \(force))")
        // Request the system to close the window.
        dismissAction(id: windowType.rawValue)

        // If forced, we manually untrack immediately, as the WindowTrackingModifier.onDisappear
        // might not fire reliably or quickly enough during rapid exit (e.g., Digital Crown press).
        if force {
            untrackWindow(windowType)
        }
        // Note: If not forced, the WindowTrackingModifier handles untracking onDisappear.
    }
    
    
    /// Close all web browser instances
    func closeAllWebBrowsers(dismissAction: DismissWindowAction) {
        print("🪟 [WindowManager] Closing all web browser instances...")
        
        // Create a copy of the set to avoid modification during iteration
        let browsersToClose = Array(browserInstances)
        
        for instanceId in browsersToClose {
            let windowId = WindowType.webBrowserInstance(instanceId)
            print("🚪 [WindowManager] Requesting dismissWindow(\(windowId))")
            dismissAction(id: windowId)
            
            // Remove from tracking immediately since we requested dismissal
            untrackBrowserWindow(instanceId)
        }
        
        print("✅ [WindowManager] All browser windows close attempt complete.")
    }
    
    /// A new function specifically for handling the scenePhase change.
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
    
    func handleImmersiveSpaceExit(openAction: OpenWindowAction, dismissAction: DismissWindowAction) {
        // Guard against re-entry from multiple dismissal events (e.g., rapid SpacesView recreation or Digital Crown press)
        guard !isHandlingImmersiveExit else {
            print("⚠️ [WindowManager] Immersive space exit already in progress, skipping.")
            return
        }
        
        print("🚀 [WindowManager] Starting robust immersive space exit handling.")
        isHandlingImmersiveExit = true
        
        // Run the sequence asynchronously to allow the UI to update and the space to close.
        Task { @MainActor in
            defer {
                // Ensure the flag is reset when the task completes. A small delay before resetting helps stability during transition.
                Task { @MainActor in
                    // 500ms delay to ensure transition stability before releasing the lock.
                    try? await Task.sleep(for: .milliseconds(500))
                    self.isHandlingImmersiveExit = false
                    print("✅ [WindowManager] Immersive space exit handling complete. Lock released.")
                }
            }
            
            // 1. Close all space windows forcefully.
            // The existing implementation of closeAllSpaceWindows uses force: true, which is correct.
            closeAllSpaceWindows(dismissAction: dismissAction)
            
            // 2. Wait for a short duration.
            // This allows the system time to finalize the immersive space dismissal and window closures.
            try? await Task.sleep(for: .milliseconds(300))
            
            // 3. Open the main window.
            // openMainWindow internally ensures it only opens if not already open.
            openMainWindow(openAction: openAction)
        }
    }

    
    
    /// Opens the main application window after the space is closed (e.g., from SpacesView.cleanupView)
    func openMainWindow(openAction: OpenWindowAction) {
        print("🪟 [WindowManager] Opening main window (tab bar)...")
        
        // Clear tracking for all space windows first
        for windowType in spaceWindowTypes {
            if activeWindows.contains(windowType.rawValue) {
                untrackWindow(windowType)
            }
        }
        
        // Check if main window is already tracked as open
        if activeWindows.contains(mainWindowType.rawValue) {
            print("✅ [WindowManager] Main window already tracked as open")
            return
        }
        
        // Check if it was recently dismissed (might be in transition)
        if recentlyDismissed.contains(mainWindowType.rawValue) {
            print("🔄 [WindowManager] Main window recently dismissed, clearing flag and opening")
            recentlyDismissed.remove(mainWindowType.rawValue)
        }
        
        // Open the main window
        print("🚀 [WindowManager] Actually opening main window")
        openAction(id: mainWindowType.rawValue)
        
        // Optimistically track it as open immediately
        activeWindows.insert(mainWindowType.rawValue)
    }
    
    // MARK: - Emergency Exit Method (for when immersive space fails to load content)
    
    /// Performs emergency cleanup when immersive space has no content
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
    
    // MARK: - Web Browser Management
    
    // Define the available browser instances (predefined)
    private let availableBrowserInstances = ["1", "2", "3", "4", "5"]
    
    /// Open the next available web browser instance
    func openWebBrowserInstance(openAction: OpenWindowAction) -> String {
        // Find the first browser instance that's not currently open
        for instanceId in availableBrowserInstances {
            let windowId = WindowType.webBrowserInstance(instanceId)
            if !activeWindows.contains(windowId) {
                print("🌐 [WindowManager] Opening browser instance: \(instanceId)")
                openAction(id: windowId)
                
                // Track the browser instance
                browserInstances.insert(instanceId)
                activeWindows.insert(windowId)
                
                return instanceId
            }
        }
        
        // If all browsers are open, just return the first one
        let firstInstance = availableBrowserInstances[0]
        print("⚠️ [WindowManager] All browser instances in use, focusing on browser \(firstInstance)")
        return firstInstance
    }
    
    /// Close a specific web browser instance
    func closeWebBrowserInstance(_ instanceId: String, dismissAction: DismissWindowAction) {
        let windowId = WindowType.webBrowserInstance(instanceId)
        
        guard browserInstances.contains(instanceId) else {
            print("⚠️ [WindowManager] Browser instance \(instanceId) not found")
            return
        }
        
        print("🚪 [WindowManager] Closing browser instance: \(instanceId)")
        dismissAction(id: windowId)
        untrackBrowserWindow(instanceId)
    }
    
    // MARK: - Helper Methods
    
    /// Check if we're currently in a space experience
    var isInSpaceExperience: Bool {
        !activeWindows.intersection(spaceWindowTypes.map { $0.rawValue }).isEmpty
    }
    
    /// Check if a specific window is open
    func isWindowOpen(_ windowType: WindowType) -> Bool {
        return activeWindows.contains(windowType.rawValue)
    }
    
    /// Check if a specific browser instance is open
    func isBrowserInstanceOpen(_ instanceId: String) -> Bool {
        return browserInstances.contains(instanceId)
    }
    
    /// Open a specific window. Tracking happens automatically via the modifier.
    func openWindow(_ windowType: WindowType, openAction: OpenWindowAction) {
         // For recently dismissed windows, always allow reopening
         if recentlyDismissed.contains(windowType.rawValue) {
             print("🔄 [WindowManager] Reopening recently dismissed window: \(windowType.rawValue)")
             recentlyDismissed.remove(windowType.rawValue)
             openAction(id: windowType.rawValue)
             return
         }
         
         // Check if already open to prevent duplicates
         guard !isWindowOpen(windowType) else {
             print("⚠️ [WindowManager] Window \(windowType.rawValue) already open, ignoring request.")
             return
         }
         
         // Additional check for main content window
         if windowType == .mainContent {
             // Check if we're already in the process of opening it
             guard !isOpeningMainWindow else {
                 print("⚠️ [WindowManager] Main window opening already in progress via openWindow")
                 return
             }
         }
         
         print("🚀 [WindowManager] Requesting openWindow(\(windowType.rawValue))")
         openAction(id: windowType.rawValue)
     }
    
    /// Close a specific window. Untracking happens automatically via the modifier.
    func closeWindow(_ windowType: WindowType, dismissAction: DismissWindowAction) {
        // Only attempt to dismiss if we currently track it as open.
        guard isWindowOpen(windowType) else { return }

        print("🚪 [WindowManager] Requesting dismissWindow(\(windowType.rawValue))")
        // Request the system to close the window.
        dismissAction(id: windowType.rawValue)
        // Note: We don't remove from activeWindows here; the WindowTrackingModifier does it when scenePhase changes.
    }
}

import SwiftUI

struct WindowTrackingModifier: ViewModifier {
    @EnvironmentObject var windowManager: WindowManager
    
    // We do not need openWindow or dismissWindow actions here anymore.
    
    let windowType: WindowType

    func body(content: Content) -> some View {
        content
            .onAppear {
                Task { @MainActor in
                    // Track when the window appears.
                    windowManager.trackWindow(windowType)
                }
            }
            .onDisappear {
                print("🪟 [WindowTracker] Window \(windowType.rawValue) disappeared (closed).")
                Task { @MainActor in
                    // Untrack when the window disappears.
                    handleWindowClosure()
                }
            }
    }
    
    // Simplified: This function now ONLY untracks the window.
    @MainActor
    private func handleWindowClosure() {
        // Untrack the window.
        // The SpacesView lifecycle methods are now solely responsible for opening the main window.
        windowManager.untrackWindow(windowType)
        
        // All logic previously in handleEnhancedWindowClosure related to calling openMainWindow() MUST be removed.
    }
}

// MARK: - View Extension
extension View {
    func trackWindow(type: WindowType) -> some View {
        self.modifier(WindowTrackingModifier(windowType: type))
    }
}
