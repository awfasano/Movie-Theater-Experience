import SwiftUI

// Simple enum to identify window types
import SwiftUI

// Simple enum to identify window types
// ADD CaseIterable conformance here
enum WindowType: String, CaseIterable { // <--- Added CaseIterable
    case chat = "chatWindow"
    case emoji = "emojiWindow"
    case movie = "movieWindow"
    case seatMap = "seatMap"
    case chatSettings = "chatSettings"
    // case tabBar = "tabBar" // This was commented out in your NavView, ensure it's needed
    case exitingWindow = "exitingWindow"
    case navBar = "navBar"
    // IMPORTANT: Add any other window types that might be managed or dismissed here
}

class WindowManager: ObservableObject {
    @Published private var activeWindows = Set<WindowType>()
    
    // Simple method to check if a window is already open
    func isWindowOpen(_ type: WindowType) -> Bool {
        activeWindows.contains(type)
    }
    
    // Add window to active set when opening
    func windowOpened(_ type: WindowType) {
        activeWindows.insert(type)
    }
    
    // Remove window from active set when closing
    func windowClosed(_ type: WindowType) {
        activeWindows.remove(type)
    }
    
    func closeAllWindows() {
        // Clear all active windows
        for windowType in WindowType.allCases {
            windowClosed(windowType)
        }
        
        // Clear the entire set as well
        activeWindows.removeAll()
        
        print("🧹 WindowManager: All windows closed")
    }
    
    // Additional helper to close specific window IDs that aren't in WindowType enum
    func closeSpaceWindows() {
        // These are specific to spaces that might not be in your WindowType enum
        let spaceWindowTypes: [String] = [
            "spaceNavBar",
            "spaceMap",
            "spaceChatWindow",
            "spaceEmojiWindow",
            "audioControls",
            "storytellerWindow",
            "userListWindow"
        ]
        
        // You might need to track these separately or add them to your WindowType enum
        print("🧹 Closing space-specific windows")
    }
}
