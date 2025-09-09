// WindowManager.swift
import SwiftUI

enum WindowType: String, CaseIterable {
    case mainContent = "mainContent"
    case tabBar = "tabBar"
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
    // Track which windows are currently active
    @Published var activeWindows: Set<String> = []
    
    // This array defines all windows that belong to the "Spaces" experience
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
    
    // The enum case for your main window that you want to return to
    let mainWindowType: WindowType = .tabBar
    
    // MARK: - Space Entry/Exit Methods
    
    /// Called when entering the immersive space
    func openSpaceEntryWindows(openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        print("🪟 [WindowManager] Opening space entry windows...")
        
        // First, dismiss the tab bar if it's open
        if activeWindows.contains(WindowType.tabBar.rawValue) {
            dismissWindow(id: WindowType.tabBar.rawValue)
            activeWindows.remove(WindowType.tabBar.rawValue)
            print("🪟 [WindowManager] Dismissed tab bar")
        }
        
        // Then open the space nav bar - ALWAYS do this
        openWindow(id: WindowType.spaceNavBar.rawValue)
        activeWindows.insert(WindowType.spaceNavBar.rawValue)
        print("✅ [WindowManager] Opened space nav bar")
    }
    
    /// Called when exiting the immersive space - enhanced version
    func closeAllSpaceWindows(dismissWindow: DismissWindowAction) {
        print("🪟 [WindowManager] Closing all space-related windows...")
        
        // Close all space-specific windows
        for windowType in spaceWindowTypes {
            if activeWindows.contains(windowType.rawValue) {
                dismissWindow(id: windowType.rawValue)
                activeWindows.remove(windowType.rawValue)
                print("  Closing: \(windowType.rawValue)")
            }
        }
        
        // Also close chat settings if it's open (it might be opened from spaces)
        if activeWindows.contains(WindowType.chatSettings.rawValue) {
            dismissWindow(id: WindowType.chatSettings.rawValue)
            activeWindows.remove(WindowType.chatSettings.rawValue)
            print("  Closing: chatSettings")
        }
        
        // Close any movie theatre windows that might still be open
        let movieWindows: [WindowType] = [.chat, .emoji, .movie, .navBar, .seatMap]
        for windowType in movieWindows {
            if activeWindows.contains(windowType.rawValue) {
                dismissWindow(id: windowType.rawValue)
                activeWindows.remove(windowType.rawValue)
                print("  Also closing movie window: \(windowType.rawValue)")
            }
        }
        
        print("✅ [WindowManager] All space windows closed")
    }
    
    /// Opens the main application window after the space is closed
    func openMainWindow(openWindow: OpenWindowAction) {
        print("🪟 [WindowManager] Opening main window (tab bar)...")
        
        // Check if tab bar is already open to prevent duplicates
        if activeWindows.contains(WindowType.tabBar.rawValue) {
            print("⚠️ [WindowManager] Tab bar already open, skipping")
            return
        }
        
        // Close any lingering space windows first
        for windowType in spaceWindowTypes {
            activeWindows.remove(windowType.rawValue)
        }
        
        // Open the tab bar window
        openWindow(id: WindowType.tabBar.rawValue)
        activeWindows.insert(WindowType.tabBar.rawValue)
    }
    
    // MARK: - Emergency Exit Method (for when immersive space is empty)
    
    /// Performs emergency cleanup when immersive space has no content
    func performEmergencyExit(
        dismissWindow: DismissWindowAction,
        openWindow: OpenWindowAction,
        dismissImmersiveSpace: @escaping () async -> Void
    ) async {
        print("🚨 [WindowManager] Performing emergency exit from empty immersive space")
        
        // Step 1: Close all space windows
        closeAllSpaceWindows(dismissWindow: dismissWindow)
        
        // Step 2: Small delay to ensure windows close
        try? await Task.sleep(for: .milliseconds(100))
        
        // Step 3: Dismiss the immersive space
        await dismissImmersiveSpace()
        
        // Step 4: Wait a moment for the immersive space to fully dismiss
        try? await Task.sleep(for: .milliseconds(200))
        
        // Step 5: Open the tab bar
        openMainWindow(openWindow: openWindow)
        
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
    
    /// Open a specific window and track it
    /// Open a specific window and track it
    func openWindow(_ windowType: WindowType, openWindow: OpenWindowAction) {
        // Check if already open to prevent duplicates
        guard !activeWindows.contains(windowType.rawValue) else {
            print("⚠️ [WindowManager] Window \(windowType.rawValue) already open")
            return
        }
        
        openWindow(id: windowType.rawValue)
        activeWindows.insert(windowType.rawValue)
        print("✅ [WindowManager] Opened window: \(windowType.rawValue)")
    }
    
    /// Close a specific window and untrack it
    func closeWindow(_ windowType: WindowType, dismissWindow: DismissWindowAction) {
        dismissWindow(id: windowType.rawValue)
        activeWindows.remove(windowType.rawValue)
    }
}
