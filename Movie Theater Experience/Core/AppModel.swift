import SwiftUI
import RealityKit // Keep if other parts of AppModel use it
import AVFoundation // For CMTime

// To make WindowOpeningRequest identifiable for .onChange
struct WindowOpeningRequest: Identifiable {
    let id = UUID() // Conformance to Identifiable
    let windowID: String
    let value: (any Codable & Sendable)? // Optional value for windows that take data

    init(windowID: String, value: (any Codable & Sendable)? = nil) {
        self.windowID = windowID
        self.value = value
    }
}

@MainActor
@Observable // Using Swift Observation
class AppModel { // Removed ObservableObject as @Observable is the modern approach
    // MARK: - Constants
    static let shared = AppModel() // If you intend to use it as a singleton
    let immersiveSpaceID = "ImmersiveSpace" // Matches your ImmersiveSpace ID
    let spacesID = "Spaces" // Matches your Spaces ImmersiveSpace ID
    
    // MARK: - Published State (or properties for @Observable)
    var selectedVideoURL: URL?
    var currentEvent: CalendarEvent?
    var isMovieWindowOpen = false
    var lastKnownPlaybackTime: CMTime = .zero
    var wasPlayingOnSwitch: Bool = false
    // var currentPlaybackTime: CMTime? // This is handled by VideoSyncService.currentTime
    var currentActiveSpace: String?
    var currentUserId: String = ""

    var resumePlaybackAfterTransition: Bool = false
    
    // Window Opening Request
    var windowToOpen: WindowOpeningRequest? = nil // Changed to optional struct

    // Private backing field for selectedSpace
    private var _selectedSpace: SpaceData?
    
    // Public computed property for selectedSpace
    var selectedSpace: SpaceData? {
        get { _selectedSpace }
        set { _selectedSpace = newValue }
    }
    
    // MARK: - Initialization
    init() {
        // The initializeUserId should be called from the App struct's onAppear
        print("📱 AppModel initialized. Ensure initializeUserId is called from App's onAppear.")
    }

    // MARK: - Update Methods for SpaceData (Struct)
    func updateSelectedSpaceSeat(to newSeat: String) {
        guard var space = _selectedSpace else { return }
        space.currentSeat = newSeat
        _selectedSpace = space
    }
    
    // MARK: - User ID Initialization
    func initializeUserId(from appStorageUserId: String, appStorage: AppStorage<String>) {
        if !appStorageUserId.isEmpty {
            self.currentUserId = appStorageUserId
            print("🔑 [AppModel] Initialized with userId from AppStorage: \(self.currentUserId)")
        } else {
            let newId = UUID().uuidString
            self.currentUserId = newId
            appStorage.wrappedValue = newId // Write back to AppStorage
            print("🔑 [AppModel] Generated and saved new userId to AppStorage: \(self.currentUserId)")
        }
        // If you also use UserDefaults directly elsewhere for "userId", ensure it's synced:
        // UserDefaults.standard.set(self.currentUserId, forKey: "userId")
    }
    
    // MARK: - Computed Properties
    var immersiveSpaceState: ImmersiveSpaceState {
        ImmersiveSpaceManager.shared.state
    }
    
    var canTransitionImmersiveSpace: Bool {
        !ImmersiveSpaceManager.shared.state.isTransitioning
    }
    
    var selectedEventID: String {
        currentEvent?.id ?? ""
    }

    var selectedDate: Date {
        currentEvent?.date ?? Date()
    }
    
    // MARK: - Public Methods for App Logic
    func cleanupImmersiveSpace() async {
        print("🧹 [AppModel] Starting immersive space cleanup request")
        await ImmersiveSpaceManager.shared.initiateCleanup()
        currentActiveSpace = nil // Reset active space tracking in AppModel
        resetAppState() // Reset other relevant app states
    }
    
    func switchToSpace(_ spaceID: String) async -> Bool {
        guard canTransitionImmersiveSpace else {
            print("❌ [AppModel] Cannot switch spaces while transitioning")
            return false
        }
        
        if currentActiveSpace == spaceID {
            print("ℹ️ [AppModel] Already in space: \(spaceID). No switch needed.")
            return true
        }
        
        if currentActiveSpace != nil {
            print("🧹 [AppModel] Cleaning up current space (\(currentActiveSpace ?? "nil")) before switching.")
            await cleanupImmersiveSpace()
        }
        
        print("🔄 [AppModel] Switching to space: \(spaceID)")
        currentActiveSpace = spaceID
        // Actual opening of immersive space is handled by UI action calling openImmersiveSpace
        return true
    }

    // Method to request opening a window
    func requestWindowOpen(id: String, value: (any Codable & Sendable)? = nil) {
        print("📬 [AppModel] Requesting to open window ID: \(id)")
        self.windowToOpen = WindowOpeningRequest(windowID: id, value: value)
    }
    
    // MARK: - Private Methods
    private func resetAppState() {
        print("🔄 [AppModel] Resetting app state (movie window, selected video/event)")
        isMovieWindowOpen = false
        selectedVideoURL = nil
        currentEvent = nil
        // Do not reset currentUserId here unless it's a full logout
    }
    
    // MARK: - Space Lifecycle Callbacks (called by ImmersiveSpaceManager delegate or similar)
    func immersiveSpaceWillOpen() {
        print("🎭 [AppModel] Immersive space will open: \(currentActiveSpace ?? "unknown")")
    }
    
    func immersiveSpaceDidOpen() {
        print("✅ [AppModel] Immersive space opened: \(currentActiveSpace ?? "unknown")")
    }
    
    func immersiveSpaceWillClose() {
        print("🔄 [AppModel] Immersive space will close: \(currentActiveSpace ?? "unknown")")
    }
    
    func immersiveSpaceDidClose() {
        print("✅ [AppModel] Immersive space closed: \(currentActiveSpace ?? "unknown")")
        if currentActiveSpace == immersiveSpaceID || currentActiveSpace == spacesID { // Or any other relevant space ID
            currentActiveSpace = nil // Clear active space if the one closing was being tracked
        }
    }
    
    func immersiveSpaceDidFailToOpen() {
        print("❌ [AppModel] Immersive space failed to open: \(currentActiveSpace ?? "unknown")")
        currentActiveSpace = nil
        resetAppState()
    }
    
    func handleEventSelection(_ event: CalendarEvent) async -> Bool {
        print("⏳ [AppModel] Preparing for event selection: \(event.title ?? "Untitled Event")")
        while ImmersiveSpaceManager.shared.isCleaningUp {
            print("⏳ [AppModel] Waiting for ImmersiveSpaceManager cleanup...")
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        guard await ImmersiveSpaceManager.shared.prepareForOpening() else {
            print("❌ [AppModel] Failed to prepare ImmersiveSpaceManager for event: \(event.title ?? "Untitled Event")")
            return false
        }
        
        print("📅 [AppModel] Setting up event: \(event.title ?? "Untitled Event")")
        currentEvent = event
        selectedVideoURL = event.videoURLObject // Assuming videoURLObject is the URL
        return true
    }
}
