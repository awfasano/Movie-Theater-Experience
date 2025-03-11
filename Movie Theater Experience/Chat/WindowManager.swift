import SwiftUI

// Simple enum to identify window types
enum WindowType: String {
    case chat = "chatWindow"
    case emoji = "emojiWindow"
    case movie = "movieWindow"
    case seatMap = "seatMap"
    case chatSettings = "chatSettings"
    case tabBar = "tabBar"
    case exitingWindow = "exitingWindow"
    case navBar = "navBar"

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
