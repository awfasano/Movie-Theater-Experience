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
}
