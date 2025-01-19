import Foundation
import SwiftUI

@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    var selectedVideoURL: URL?
    var immersiveSpaceState = ImmersiveSpaceState.closed
    var currentEvent: CalendarEvent?
    var isMovieWindowOpen = false
    
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    
    // Keep your existing functions
    func setCurrentEvent(_ event: CalendarEvent) {
        self.currentEvent = event
        self.selectedVideoURL = event.videoURLObject
    }
    
    // Enhance the transition handler to include window management
    func handleImmersiveSpaceTransition(to state: ImmersiveSpaceState) {
        if state == .closed && !isMovieWindowOpen, let _ = selectedVideoURL {
            isMovieWindowOpen = true
        }
        immersiveSpaceState = state
    }
    
    func handleMovieWindowClosure() {
        isMovieWindowOpen = false
    }
    
    // Add new helper functions for state management
    func toggleMovieWindow() {
        isMovieWindowOpen.toggle()
    }
    
    // Helper to check if we can transition immersive space
    func canTransitionImmersiveSpace() -> Bool {
        return immersiveSpaceState != .inTransition
    }
    
    // Helper to check if we should auto-show movie window
    func shouldShowMovieWindow() -> Bool {
        return selectedVideoURL != nil && !isMovieWindowOpen
    }
}
