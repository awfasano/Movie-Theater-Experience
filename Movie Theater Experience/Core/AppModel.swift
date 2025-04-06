import SwiftUI
import RealityKit
import AVFoundation

@MainActor
@Observable
class AppModel: ObservableObject {
    // MARK: - Constants
    static let shared = AppModel()
    let immersiveSpaceID = "ImmersiveSpace"
    let spacesID = "Spaces"
    
    // MARK: - Published State
    var selectedVideoURL: URL?
    var currentEvent: CalendarEvent?
    var isMovieWindowOpen = false
    var lastKnownPlaybackTime: CMTime = .zero
    var wasPlayingOnSwitch: Bool = false
    var currentPlaybackTime: CMTime?
    var currentActiveSpace: String?
    
    // Private backing field
    private var _selectedSpace: SpaceData?
    
    // Public computed property
    var selectedSpace: SpaceData? {
        get { _selectedSpace }
        set { _selectedSpace = newValue }
    }
    
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
        currentActiveSpace = nil
        resetAppState()
    }
    
    func switchToSpace(_ spaceID: String) async -> Bool {
        guard canTransitionImmersiveSpace else {
            print("❌ Cannot switch spaces while transitioning")
            return false
        }
        
        // If we're already in this space, no need to switch
        if currentActiveSpace == spaceID {
            return true
        }
        
        // Cleanup current space if any
        if currentActiveSpace != nil {
            await cleanupImmersiveSpace()
        }
        
        print("🔄 Switching to space: \(spaceID)")
        currentActiveSpace = spaceID
        return true
    }
    
    // MARK: - Private Methods
    private func resetAppState() {
        print("🔄 Resetting app state")
        isMovieWindowOpen = false
        selectedVideoURL = nil
        currentEvent = nil
    }
    
    // MARK: - Space Lifecycle Methods
    func immersiveSpaceWillOpen() {
        print("🎭 Immersive space will open: \(currentActiveSpace ?? "unknown")")
    }
    
    func immersiveSpaceDidOpen() {
        print("✅ Immersive space opened: \(currentActiveSpace ?? "unknown")")
    }
    
    func immersiveSpaceWillClose() {
        print("🔄 Immersive space will close: \(currentActiveSpace ?? "unknown")")
    }
    
    func immersiveSpaceDidClose() {
        print("✅ Immersive space closed: \(currentActiveSpace ?? "unknown")")
        currentActiveSpace = nil
    }
    
    func immersiveSpaceDidFailToOpen() {
        print("❌ Immersive space failed to open: \(currentActiveSpace ?? "unknown")")
        currentActiveSpace = nil
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
