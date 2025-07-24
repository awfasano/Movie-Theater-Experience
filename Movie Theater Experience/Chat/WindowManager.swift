
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
