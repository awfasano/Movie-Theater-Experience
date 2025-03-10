import SwiftUI
import RealityKit
import AVFoundation


@MainActor
@Observable
class AppModel:ObservableObject {
    // MARK: - Constants
    static let shared = AppModel()
    let immersiveSpaceID = "ImmersiveSpace"
    
    // MARK: - Published State
    var selectedVideoURL: URL?
    var currentEvent: CalendarEvent?
    var isMovieWindowOpen = false
    var lastKnownPlaybackTime: CMTime = .zero
    var wasPlayingOnSwitch: Bool = false
    var currentPlaybackTime: CMTime?

    
    // MARK: - Private Properties
    private let spaceManager = ImmersiveSpaceManager.shared
    
    // MARK: - Computed Properties
    var immersiveSpaceState: ImmersiveSpaceState {
        spaceManager.state
    }
    
    var canTransitionImmersiveSpace: Bool {
        !immersiveSpaceState.isTransitioning
    }
    
    var selectedEventID: String {
        currentEvent?.id ?? ""
    }

    var selectedDate: Date {
        currentEvent?.date ?? Date()
    }
    
    
    // MARK: - Public Methods

    
    func cleanupImmersiveSpace() async {
        print("🧹 Starting immersive space cleanup")
        await spaceManager.initiateCleanup()
        resetAppState()
    }
    
    // MARK: - Private Methods
    private func resetAppState() {
        print("🔄 Resetting app state")
        isMovieWindowOpen = false
        selectedVideoURL = nil
        currentEvent = nil
    }
    func immersiveSpaceWillOpen() {
        print("🎭 Immersive space will open")
    }
    
    func immersiveSpaceDidOpen() {
        print("✅ Immersive space opened")
    }
    
    func immersiveSpaceWillClose() {
        print("🔄 Immersive space will close")
    }
    
    func immersiveSpaceDidClose() {
        print("✅ Immersive space closed")
    }
    
    func immersiveSpaceDidFailToOpen() {
        print("❌ Immersive space failed to open")
        resetAppState()
    }
    
    func handleEventSelection(_ event: CalendarEvent) async -> Bool {
        // Wait for any ongoing cleanup
        while spaceManager.isCleaningUp {
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        guard await spaceManager.prepareForOpening() else {
            print("❌ Failed to prepare for event: \(event.title)")
            return false
        }
        
        print("📅 Setting up event: \(event.title)")
        currentEvent = event
        selectedVideoURL = event.videoURLObject
        return true
    }
    
}

