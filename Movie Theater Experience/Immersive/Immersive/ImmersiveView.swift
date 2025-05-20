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
    @State private var showEndScreen = false

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
        ZStack {
            // ───────────────────────────────────────────────────────── Reality‑Kit scene
            RealityView { content in
                do { try await setupTheatreEnvironment(in: content) }
                catch { print("❌ Failed to set up theatre environment: \(error)") }
            }
            // ─── Original modifiers (unchanged) ───────────────────────────────────────
            .onChange(of: appModel.isMovieWindowOpen) { _, newValue in
                Task { @MainActor in await handleMovieWindowChange(newValue) }
            }
            .onChange(of: sharedSelection.selectedSeatEntity) { _, newSeat in
                Task { @MainActor in if let seat = newSeat { await adjustViewerPosition(for: seat) } }
            }
            .onChange(of: appModel.selectedVideoURL) { _, newURL in
                Task { @MainActor in await handleVideoURLChange(newURL) }
            }
            .onAppear {
                Task { @MainActor in
                    await onViewAppear()
                    configureImmersiveSpaceManager()
                }
            }
            .onDisappear {
                Task { @MainActor in await handleCleanup() }
            }
            .alert("Access Denied", isPresented: $showAccessDeniedAlert) {
                Button("OK", role: .cancel) { }
            } message: { Text(accessDeniedMessage) }

            // ───────────────────────────────────────────────────────── End‑of‑movie UI
            if showEndScreen {
                EndScreen {                     // Exit‑button action
                    Task { @MainActor in await dismissImmersiveSpace() }
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)                      // keep it above RealityView
            }
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
            guard
                let originalScreenMesh = findModelEntity(byName: Constants.screenEntityName, in: theatre)
                // let modelEntity = screenMesh as? ModelEntity // originalScreenMesh is already ModelEntity
            else {
                print("❌ Original screen mesh ('\(Constants.screenEntityName)') not found in theatre entity.")
                return
            }

            print("✅ Original screen mesh located (\(originalScreenMesh.name)).")

            // 1️⃣ Make the original screen mesh itself dark so its surface doesn't show through
            //    This is important if the VideoPlane doesn't perfectly cover it or has transparency.
            var matte = UnlitMaterial(color: .black)
            originalScreenMesh.model?.materials = [matte]
            // originalScreenMesh.isEnabled = false; // Alternatively, hide the original mesh entirely if VideoPlane always covers it

            // 2️⃣ Create / obtain the dedicated VideoPlane using the original mesh as a reference
            //    videoPlane will be a child of originalScreenMesh
            let videoSurfacePlane = TheatreEntityWrapper.shared.videoPlane(for: originalScreenMesh)
            theatreEntityWrapper.screenEntity = videoSurfacePlane   // Track the VideoPlane

            // 3️⃣ If a video is pending, configure it on the videoSurfacePlane
            Task {
                if let videoURL = appModel.selectedVideoURL,
                   !appModel.isMovieWindowOpen,
                   case .open = spaceManager.state {

                    print("🎥 Binding video to videoSurfacePlane (from configureScreenEntities)...")
                    // Pass the videoSurfacePlane here
                    await configureVideoWithSync(screenEntity: videoSurfacePlane, url: videoURL)
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
           // let theatre = theatreEntityWrapper.entity, // Not needed if screenEntity is already set
           let videoPlane = theatreEntityWrapper.screenEntity { // Use videoPlane if available
            await configureVideoWithSync(screenEntity: videoPlane, url: videoURL)
        } else if !appModel.isMovieWindowOpen, let videoURL = appModel.selectedVideoURL, let theatre = theatreEntityWrapper.entity {
            // Fallback if videoPlane isn't set up yet but theatre is (e.g., first appearance before configureScreenEntities fully completes its async block)
            // We need to ensure configureScreenEntities has run and set up the videoPlane.
            // The call inside configureScreenEntities should ideally handle this.
            // For robustness, one could wait for theatreEntityWrapper.screenEntity to not be nil here, or
            // rely on configureScreenEntities to call configureVideoWithSync.
            // The current structure in configureScreenEntities seems to cover this.
            print("⏳ ImmersiveView.onViewAppear: VideoPlane not yet available, configureScreenEntities will handle video setup.")
        }
    }
    
    private func handleCleanup() async {
        print("🧹 Handling immersive space cleanup…")

        // 1️⃣ decide whether to keep the player
        let keepPlayer = appModel.isMovieWindowOpen
        videoPlayerManager.clearAllResources(keepPlayer: keepPlayer)

        // 2️⃣ save snapshot & pause if needed
        if let player = videoPlayerManager.player {
            let pos = player.currentTime().seconds
            let playing = player.timeControlStatus == .playing
            videoSyncService.storePlaybackSnapshot(position: pos, isPlaying: playing)

            if playing {
                await videoSyncService.handlePlayPause(isPlaying: false)
            }
        }

        // 3️⃣ coordinated cleanup
        await videoSyncService.cleanup(level: keepPlayer ? .light : .full)
        await lightingManager.stopMovieLightingEffect()
        spatialAudioManager.cleanup()
        await theatreEntityWrapper.cleanup()
        await spaceManager.initiateCleanup()

        print("✅ Immersive space cleanup complete.")
    }


    // MARK: - Observing isMovieWindowOpen
    private func handleMovieWindowChange(_ isMovieWindowOpen: Bool) async {
        if isMovieWindowOpen {
            print("📱 MovieWindow opened - Hiding immersive screen entity (VideoPlane)")
            if let videoPlane = theatreEntityWrapper.screenEntity { // This should be the VideoPlane
                await MainActor.run {
                    videoPlane.isEnabled = false
                    print("⬛ Immersive screen (VideoPlane) **HIDDEN**")
                }
            }
            // The VideoPlayerManager might also apply a black material before hiding
            // videoPlayerManager.setScreenVisibility(screenEntity: theatreEntityWrapper.screenEntity, visible: false)
            return
        }

        // MovieWindow closed - Restoring immersive screen entity
        print("📱 MovieWindow closed - Restoring immersive screen entity (VideoPlane)")

        guard let videoPlane = theatreEntityWrapper.screenEntity else {
            print("❌ MovieWindow closed, but no videoPlane (theatreEntityWrapper.screenEntity) found to restore.")
            // This would be an issue. Maybe the theatre needs full reconfiguration?
            // Or re-run configureScreenEntities if theatreEntityWrapper.entity exists.
            if let theatre = theatreEntityWrapper.entity {
                print("⚠️ Attempting to re-run configureScreenEntities as videoPlane was nil.")
                await configureScreenEntities(in: theatre) // This will re-establish the videoPlane
            }
            return
        }

        guard let videoURL = appModel.selectedVideoURL else {
            print("❌ MovieWindow closed, but no selectedVideoURL found.")
            return
        }
        
        await MainActor.run {
            videoPlane.isEnabled = true // Make the VideoPlane visible
            print("🎬 Immersive screen (VideoPlane) **VISIBLE**")
        }

        // Pass the videoPlane to configureVideoWithSync
        await configureVideoWithSync(screenEntity: videoPlane, url: videoURL)

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
    
    // MARK: - Handling selectedVideoURL changes
    private func handleVideoURLChange(_ newURL: URL?) async {
        guard let newURL = newURL,
              let videoPlane = theatreEntityWrapper.screenEntity, // Use the VideoPlane
              !appModel.isMovieWindowOpen else {
            // If movie window is open, or no videoPlane, do nothing here.
            // MovieWindow will handle its own video change.
            // If immersive and no videoPlane, configureScreenEntities should run first.
            return
        }
        
        print("🎥 ImmersiveView.handleVideoURLChange - Refreshing immersive video on VideoPlane.")
        await configureVideoWithSync(screenEntity: videoPlane, url: newURL)
    }
    
    // MARK: - Configuring Video with Sync
    // MARK: - Configure a video on the immersive screen, keeping it in sync
    private func configureVideoWithSync(
        screenEntity: ModelEntity,
        url: URL
    ) async {
        print("🎥 [Immersive] configureVideoWithSync started")

        // ── 0. Sanity checks ────────────────────────────────────────────────
        guard let currentEvent = appModel.currentEvent else {
            print("❌ No current event found – aborting video load")
            return
        }
        let eventId = currentEvent.id ?? ""
        let userId  = getUserId()

        // ── 1. Configure / reuse the sync service ──────────────────────────
        if !videoSyncService.isConfigured(for: eventId, userId: userId) {
            print("🔄 Sync not configured yet – configuring now…")
            guard await videoSyncService.configureSync(
                    eventId: eventId,
                    userId:  userId,
                    event:   currentEvent)
            else {
                print("❌ Sync configuration failed")
                handleSyncFailure()
                return
            }
            print("✅ Sync configured")
            try? await Task.sleep(for: .milliseconds(300))   // let listeners settle
        } else {
            print("ℹ️ Sync already configured – re‑using existing session")
        }

        // ── 2. Create or update the RealityKit video material ──────────────
        let videoConfigured = await withCheckedContinuation { continuation in
            Task { @MainActor in
                videoPlayerManager.configureVideo(
                    for: screenEntity,
                    videoURL: url
                ) { success in
                    if success {
                        print("✅ Video material configured")
                    } else {
                        print("❌ Video material configuration failed")
                    }
                    continuation.resume(returning: success)
                }
            }
        }

        guard videoConfigured else { return }

        // ── 3. Wait for the underlying AVPlayer to become ready ────────────
        var attempts = 0
        while !videoPlayerManager.isPlaybackReady && attempts < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }
        guard videoPlayerManager.isPlaybackReady else {
            print("❌ Player readiness timeout")
            return
        }

        // ── 4. Attach the global “video ended” handler (once) ──────────────
        setupVideoEndHandler()

        // ── 5. Start sync with the player instance (or resume) ─────────────
        if let player = videoPlayerManager.player {
            await videoSyncService.startSync(with: player)
            print("▶️ Player handed to VideoSyncService for live sync")
        }

        print("✅ [Immersive] configureVideoWithSync finished")
    }
    
    // MARK: - Video End Handler
    // MARK: - Video‑End handler
    private func setupVideoEndHandler() {
        videoSyncService.setupVideoEndHandler {
            Task { @MainActor in
                // 1️⃣  Show the confetti overlay
                withAnimation { showEndScreen = true }

                // 2️⃣  (Optional) auto‑hide overlay after 4 s
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { showEndScreen = false }
                }

                // 3️⃣  Gather watch statistics before we tear anything down
                let stats = await videoSyncService.getWatchStats()

                // 4️⃣  Begin internal cleanup of the immersive space
                await spaceManager.initiateCleanup()

                // 5️⃣  Close auxiliary windows
                dismissWindow(id: "chatWindow")
                dismissWindow(id: "emojiWindow")
                dismissWindow(id: "movieWindow")
                dismissWindow(id: "seatMap")
                dismissWindow(id: "chatSettings")
                dismissWindow(id: "navBar")

                // 6️⃣  Present a stats / exit window (if you use one)
                try? await Task.sleep(for: .milliseconds(200))     // let windows settle
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
        Task { await videoSyncService.handlePlayPause(isPlaying: false) }
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
