import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation
import Combine

@available(visionOS 1.0, *)
struct ImmersiveView: View {
    // MARK: - Environment
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    // Added: Environment object for the window manager.
    @EnvironmentObject var windowManager: WindowManager

    // MARK: - Observed / State Objects
    @ObservedObject private var sharedSelection = SharedSeatSelection.shared
    @ObservedObject private var theatreEntityWrapper = TheatreEntityWrapper.shared
    
    private let spaceManager = ImmersiveSpaceManager.shared
    private let videoSyncService = VideoSyncService.shared
    
    @StateObject private var videoPlayerManager: VideoPlayerManager
    @StateObject private var lightingManager = TheatreLightingManager()
    @StateObject private var spatialAudioManager = SpatialAudioManager()
    
    // MARK: - Internal States
    @State private var showAccessDeniedAlert = false
    @State private var accessDeniedMessage = ""
    
    // MARK: - Constants
    private enum Constants {
        static let screenEntityName = "polySurface11205_lambert184_0"
        static let initialTheatrePosition = SIMD3<Float>(0, -1, -3)
        static let viewerHeight: Float = 0
    }
    
    // MARK: - Init
    init() {
        let syncService = VideoSyncService.shared
        _videoPlayerManager = StateObject(wrappedValue: VideoPlayerManager(videoSyncService: syncService))
        _lightingManager = StateObject(wrappedValue: TheatreLightingManager())
        _spatialAudioManager = StateObject(wrappedValue: SpatialAudioManager())
    }
    
    // MARK: - Body
    var body: some View {
        RealityView { content in
            do {
                try await setupTheatreEnvironment(in: content)
            } catch {
                print("❌ Failed to setup theatre environment: \(error)")
            }
        }
        // 1) Watch for changes in the "Movie Window Open" flag
        .onChange(of: appModel.isMovieWindowOpen) { _, newValue in
            Task { @MainActor in
                await handleMovieWindowChange(newValue)
            }
        }
        // 2) Example seat selection logic
        .onChange(of: sharedSelection.selectedSeatEntity) { _, newSeat in
            Task { @MainActor in
                if let seat = newSeat {
                    await adjustViewerPosition(for: seat)
                }
            }
        }
        // 3) If selectedVideoURL changes (and movie window closed), re-load in immersive
        .onChange(of: appModel.selectedVideoURL) { _, newURL in
            Task { @MainActor in
                await handleVideoURLChange(newURL)
            }
        }
        // 4) Lifecycle events
        .onAppear {
            Task { @MainActor in
                await onViewAppear()
                configureImmersiveSpaceManager()
            }
        }
        .onDisappear {
            Task { @MainActor in
                await handleCleanup()
            }
        }
        // 5) Alert for "access denied"
        .alert("Access Denied", isPresented: $showAccessDeniedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(accessDeniedMessage)
        }
    }
    
    private func configureImmersiveSpaceManager() {
        let dismissImmersiveSpaceAction = dismissImmersiveSpace
        let dismissWindowAction = dismissWindow
        let openWindowAction = openWindow
        let openImmersiveSpaceAction = openImmersiveSpace
        
        ImmersiveSpaceManager.shared.configure(
            dismissImmersiveSpace: {
                await dismissImmersiveSpaceAction()
            },
            dismissWindow: { windowId in
                dismissWindowAction(id: windowId)
            },
            openWindow: { windowId in
                openWindowAction(id: windowId)
            },
            openImmersiveSpace: {
                return await openImmersiveSpaceAction(id: "immersiveSpaceID") == .opened
            }
        )
    }
    
    // MARK: - Setup
    private func setupTheatreEnvironment(in content: RealityViewContent) async throws {
        print("🎬 Setting up theatre environment")
        
        // Wait for any ongoing cleanup
        while spaceManager.isCleaningUp {
            print("⏳ Waiting for cleanup to complete...")
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Clean up the old entity if any
        await TheatreEntityWrapper.shared.cleanup()

        // Load a new "Movie" entity from your .reality file
        let theatreEntity = try await Entity(named: "Movie", in: realityKitContentBundle)
        theatreEntity.position = Constants.initialTheatrePosition
        
        // Add to RealityView
        await MainActor.run {
            content.add(theatreEntity)
            theatreEntityWrapper.setEntity(theatreEntity)
        }
        
        // Let everything settle
        try? await Task.sleep(for: .milliseconds(50))
        
        // Configure audio & lighting
        await MainActor.run {
            spatialAudioManager.configureSpeakersFromTheater(theatreEntity)
        }
        await lightingManager.configureLighting(theatreEntity: theatreEntity)
        
        // Find the screen entity and init if needed
        await configureScreenEntities(in: theatreEntity)
        
        print("✅ Theatre environment setup complete")
    }

    private func configureScreenEntities(in theatre: Entity) async {
        await MainActor.run {
            // 1️⃣ Find the screen entity
            guard let screenEntity = findModelEntity(byName: Constants.screenEntityName, in: theatre),
                  let modelEntity = screenEntity as? ModelEntity else {
                print("❌ Failed to find screen entity")
                return
            }
            
            print("✅ Found screen entity: \(screenEntity.name)")

            // 2️⃣ Apply a temporary white material for testing
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .black)  // Ensures visibility
            material.roughness = 0.3
            material.metallic = 0.0
            
            // 3️⃣ Ensure RealityKit updates the material
            modelEntity.model?.materials = [material]
            
            print("✅ Applied new white material to screen entity.")

            // 4️⃣ Check if a video should be played
            Task {
                if let videoURL = appModel.selectedVideoURL,
                   !appModel.isMovieWindowOpen,
                   case .open = spaceManager.state {
                    print("🎥 Configuring video with sync...")
                    await configureVideoWithSync(screenEntity: screenEntity, url: videoURL)
                }
            }
        }
    }
    
    // MARK: - Lifecycle: Appear / Disappear
    private func onViewAppear() async {
        print("👋 ImmersiveView appeared")
        
        // Configure space manager's environment closures
        spaceManager.configure(
            dismissImmersiveSpace: { await dismissImmersiveSpace() },
            dismissWindow: { windowId in dismissWindow(id: windowId) },
            openWindow: { windowId in openWindow(id: windowId) },
            openImmersiveSpace: {
                switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                case .opened:       return true
                case .error, .userCancelled, _:
                    return false
                }
            }
        )
        
        // Indicate that we've opened successfully
        spaceManager.handleOpenSuccess()
        
        // Assign your managers
        videoPlayerManager.setSpatialAudioManager(spatialAudioManager)
        theatreEntityWrapper.videoPlayerManager = videoPlayerManager
        
        // If we have a video & the user is not currently in a pop-out window, load it
        if !appModel.isMovieWindowOpen,
           let videoURL = appModel.selectedVideoURL,
           let theatre = theatreEntityWrapper.entity,
           let screen = findModelEntity(byName: Constants.screenEntityName, in: theatre) {
            await configureVideoWithSync(screenEntity: screen, url: videoURL)
        }
    }
    
    private func handleCleanup() async {
        print("🧹 Handling immersive space cleanup...")

        // 1️⃣ Determine if we should keep the player alive
        let keepPlayer = appModel.isMovieWindowOpen  // Don't stop video if MovieWindow is open
        videoPlayerManager.clearAllResources(keepPlayer: keepPlayer)

        // 2️⃣ Save playback state
        if let player = videoPlayerManager.player {
            let position = player.currentTime().seconds
            let isPlaying = player.timeControlStatus == .playing

            videoSyncService.storePlaybackSnapshot(position: position, isPlaying: isPlaying)

            if isPlaying {
                videoSyncService.handlePlayPause(isPlaying: false)
            }
        }

        // 3️⃣ Cleanup logic
        videoSyncService.cleanup(level: keepPlayer ? .light : .full)
        await lightingManager.stopMovieLightingEffect()
        spatialAudioManager.cleanup()
        await theatreEntityWrapper.cleanup()
        await spaceManager.initiateCleanup()

        print("✅ Immersive space cleanup complete.")
    }

    // MARK: - Observing isMovieWindowOpen
    private func handleMovieWindowChange(_ isMovieWindowOpen: Bool) async {
        if isMovieWindowOpen {
            print("📱 MovieWindow opened - Hiding immersive screen entity")
            
            // Hide immersive screen entity
            if let screenEntity = theatreEntityWrapper.screenEntity {
                await MainActor.run {
                    screenEntity.isEnabled = false
                    print("⬛ Immersive screen **HIDDEN**")
                }
            }
            return
        }

        print("📱 MovieWindow closed - Restoring immersive screen entity")

        if let theatre = theatreEntityWrapper.entity,
           let screenEntity = findModelEntity(byName: Constants.screenEntityName, in: theatre),
           let videoURL = appModel.selectedVideoURL {
            
            await MainActor.run {
                screenEntity.isEnabled = true
                print("🎬 Immersive screen **VISIBLE**")
            }

            await configureVideoWithSync(screenEntity: screenEntity, url: videoURL)

            if let snapshot = videoSyncService.currentSnapshot {
                print("📸 Restoring snapshot - position: \(snapshot.position), playing: \(snapshot.isPlaying)")
                
                guard let player = videoPlayerManager.player else {
                    print("❌ No player found after restoring screen entity")
                    return
                }

                await player.seek(to: CMTime(seconds: snapshot.position, preferredTimescale: 1000))
                
                if snapshot.isPlaying {
                    print("▶️ Resuming playback")
                    player.play()
                } else {
                    print("⏸️ Ensuring paused state")
                    player.pause()
                }
            }
        }
    }
    
    // MARK: - Handling selectedVideoURL changes
    private func handleVideoURLChange(_ newURL: URL?) async {
        guard let newURL = newURL,
              let theatre = theatreEntityWrapper.entity,
              let screenEntity = findModelEntity(byName: Constants.screenEntityName, in: theatre),
              !appModel.isMovieWindowOpen else {
            return
        }
        
        // If the movie window is closed, refresh the immersive
        await configureVideoWithSync(screenEntity: screenEntity, url: newURL)
    }
    
    // MARK: - Configuring Video with Sync
    private func configureVideoWithSync(screenEntity: ModelEntity, url: URL) async {
        print("🎥 Starting video configuration with sync")
        
        guard let currentEvent = appModel.currentEvent else {
            print("❌ No current event found")
            return
        }

        // 1. Configure sync service first
        print("🔄 Configuring sync service...")
        guard videoSyncService.configureSync(
            eventId: currentEvent.id ?? "",
            userId: getUserId(),
            event: currentEvent
        ) else {
            print("❌ Failed to configure sync service")
            handleSyncFailure()
            return
        }
        print("✅ Sync service configured")

        // 2. Wait for any pending operations
        try? await Task.sleep(for: .milliseconds(300))

        // 3. Configure video player with completion handling
        let success = await withCheckedContinuation { continuation in
            Task { @MainActor in
                videoPlayerManager.configureVideo(for: screenEntity, videoURL: url) { success in
                    if success {
                        print("✅ Video player configuration complete")
                    } else {
                        print("❌ Video player configuration failed")
                    }
                    continuation.resume(returning: success)
                }
            }
        }

        guard success else {
            print("❌ Video configuration failed")
            return
        }

        // 4. Wait for player readiness
        let maxAttempts = 50
        var attempts = 0
        while !videoPlayerManager.isPlaybackReady && attempts < maxAttempts {
            try? await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }

        guard videoPlayerManager.isPlaybackReady else {
            print("❌ Player readiness timeout")
            return
        }

        // 5. Setup video end handler
        setupVideoEndHandler()
    }
    
    // MARK: - Video End Handler
    private func setupVideoEndHandler() {
        videoSyncService.setupVideoEndHandler {
            Task { @MainActor in
                // Get stats before cleanup
                let stats = videoSyncService.getWatchStats()
                
                // Cleanup immersive space
                await spaceManager.initiateCleanup()
                
                // Dismiss all windows
                dismissWindow(id: "chatWindow")
                dismissWindow(id: "emojiWindow")
                dismissWindow(id: "movieWindow")
                dismissWindow(id: "seatMap")
                dismissWindow(id: "chatSettings")
                dismissWindow(id: "navBar")
                
                // Show stats window
                try? await Task.sleep(for: .milliseconds(100))
                if !windowManager.isWindowOpen(.exitingWindow) {
                    openWindow(id: "exitingWindow", value: stats)
                    windowManager.windowOpened(.exitingWindow)
                }
            }
        }
    }
    
    // MARK: - Seat Position Adjustment
    private func adjustViewerPosition(for selectedSeat: Entity) async {
        guard let theatre = theatreEntityWrapper.entity else { return }
        
        await MainActor.run {
            let seatPos = selectedSeat.position(relativeTo: nil)
            let viewerPos = SIMD3<Float>(seatPos.x, seatPos.y + Constants.viewerHeight, seatPos.z)
            
            // We'll move the entire theatre so the seat lines up with the user
            let shift = SIMD3<Float>(-viewerPos.x, -viewerPos.y, -viewerPos.z)
            
            withAnimation(.smooth(duration: 0.8)) {
                theatre.position += shift
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                spatialAudioManager.updateSpeakerPositions(theatre)
            }
        }
    }
    
    private func handleSyncFailure() {
        print("❌ Video sync failed")
        videoSyncService.handlePlayPause(isPlaying: false)
        showAccessDeniedAlert = true
        accessDeniedMessage = "This event is not currently available for viewing."
    }
    
    // MARK: - Helpers
    private func findModelEntity(byName name: String, in entity: Entity) -> ModelEntity? {
        if let m = entity as? ModelEntity, entity.name.contains(name) {
            return m
        }
        for child in entity.children {
            if let found = findModelEntity(byName: name, in: child) {
                return found
            }
        }
        return nil
    }
    
    private func getUserId() -> String {
        if let storedUserId = UserDefaults.standard.string(forKey: "userId") {
            return storedUserId
        } else {
            let newUserId = UUID().uuidString
            UserDefaults.standard.set(newUserId, forKey: "userId")
            return newUserId
        }
    }
}
