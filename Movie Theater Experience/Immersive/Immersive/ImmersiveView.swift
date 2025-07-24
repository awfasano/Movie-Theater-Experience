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

    @EnvironmentObject var windowManager: WindowManager

    // MARK: - Observed / State Objects
    @ObservedObject private var sharedSelection = SharedSeatSelection.shared
    @ObservedObject private var theatreEntityWrapper = TheatreEntityWrapper.shared
    
    private let spaceManager = ImmersiveSpaceManager.shared
    @State private var videoSyncService = VideoSyncService.shared
    
    @StateObject private var videoPlayerManager: VideoPlayerManager
    @StateObject private var lightingManager = TheatreLightingManager()
    @StateObject private var spatialAudioManager = SpatialAudioManager()
    
    // MARK: - Internal States
    @State private var showAccessDeniedAlert = false
    @State private var accessDeniedMessage = ""
    @State private var isConfiguring = false

    
    // MARK: - Constants
    private enum Constants {
        static let screenEntityName = "polySurface11205_lambert184_0"
        static let initialTheatrePosition = SIMD3<Float>(0, -1, -3)
        static let viewerHeight: Float = 0
    }
    
    // MARK: - Init
    init() {
        // --- FIX #1 IS HERE ---
        // VideoPlayerManager initializer no longer takes a videoSyncService argument.
        _videoPlayerManager = StateObject(wrappedValue: VideoPlayerManager())
        _lightingManager = StateObject(wrappedValue: TheatreLightingManager())
        _spatialAudioManager = StateObject(wrappedValue: SpatialAudioManager())
        print("🎬 ImmersiveView initialized with its managers.")
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            RealityView { content in
                do {
                    print(" realtà [ImmersiveView] RealityView content closure: Setting up theatre environment.")
                    try await setupTheatreEnvironment(in: content)
                }
                catch { print("❌ [ImmersiveView] Failed to set up theatre environment: \(error)") }
            }
            .onChange(of: appModel.isMovieWindowOpen) { _, newValue in
                Task { @MainActor in
                    print("🎬 [ImmersiveView] Detected appModel.isMovieWindowOpen change to: \(newValue)")
                    await handleMovieWindowChange(newValue)
                }
            }
            .onChange(of: sharedSelection.selectedSeatEntity) { _, newSeat in
                Task { @MainActor in
                    if let seat = newSeat {
                        print("🪑 [ImmersiveView] Detected selectedSeatEntity change.")
                        await adjustViewerPosition(for: seat)
                    }
                }
            }
            .onChange(of: appModel.selectedVideoURL) { _, newURL in
                Task { @MainActor in
                    print("🎬 [ImmersiveView] Detected selectedVideoURL change.")
                    await handleVideoURLChange(newURL)
                }
            }
            .onAppear {
                Task { @MainActor in
                    print("👋 [ImmersiveView] .onAppear triggered.")
                    await onViewAppear()
                }
            }
            .onDisappear {
                Task { @MainActor in
                    print("💨 [ImmersiveView] .onDisappear triggered.")
                    await handleCleanup()
                }
            }
            .alert("Access Denied", isPresented: $showAccessDeniedAlert) {
                Button("OK", role: .cancel) { }
            } message: { Text(accessDeniedMessage) }

            if showEndScreen {
                EndScreen {
                    Task { @MainActor in await dismissImmersiveSpace() }
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
            }
        }
    }

    private func configureImmersiveSpaceManager() {
        print("🛠️ [ImmersiveView] Configuring ImmersiveSpaceManager closures.")
        let dismissImmersiveSpaceAction = dismissImmersiveSpace
        let dismissWindowAction = dismissWindow
        let openWindowAction = openWindow
        let openImmersiveSpaceAction = openImmersiveSpace
        
        ImmersiveSpaceManager.shared.configure(
            dismissImmersiveSpace: {
                print("🚪 [ImmersiveView via SpaceManager] Dismissing immersive space.")
                await dismissImmersiveSpaceAction()
            },
            dismissWindow: { windowId in
                print("🚪 [ImmersiveView via SpaceManager] Dismissing window: \(windowId)")
                dismissWindowAction(id: windowId)
            },
            openWindow: { windowId in
                print("🚪 [ImmersiveView via SpaceManager] Opening window: \(windowId)")
                openWindowAction(id: windowId)
            },
            openImmersiveSpace: {
                print("🚪 [ImmersiveView via SpaceManager] Attempting to open immersive space: \(appModel.immersiveSpaceID)")
                let result = await openImmersiveSpaceAction(id: appModel.immersiveSpaceID)
                print("🚪 [ImmersiveView via SpaceManager] Open immersive space result: \(result)")
                return result == .opened
            }
        )
    }
    
    // MARK: - Setup
    private func setupTheatreEnvironment(in content: RealityViewContent) async throws {
        print("🎭 [ImmersiveView] setupTheatreEnvironment: Starting.")
        
        while spaceManager.isCleaningUp {
            print("⏳ [ImmersiveView] Waiting for SpaceManager cleanup to complete...")
            try? await Task.sleep(for: .milliseconds(100))
        }

        await TheatreEntityWrapper.shared.cleanup()

        print("🧩 [ImmersiveView] Loading 'Movie' entity from bundle.")
        let theatreEntity = try await Entity(named: "Movie", in: realityKitContentBundle)
        theatreEntity.position = Constants.initialTheatrePosition
        
        await MainActor.run {
            print("➕ [ImmersiveView] Adding theatreEntity to RealityView content.")
            content.add(theatreEntity)
            theatreEntityWrapper.setEntity(theatreEntity)
        }
        
        try? await Task.sleep(for: .milliseconds(50))
        
        print("🔊 [ImmersiveView] Configuring spatial audio and lighting.")
        await MainActor.run {
            spatialAudioManager.configureSpeakersFromTheater(theatreEntity)
        }
        await lightingManager.configureLighting(theatreEntity: theatreEntity)
        
        print("🖥️ [ImmersiveView] Configuring screen entities.")
        await configureScreenEntities(in: theatreEntity)
        
        print("✅ [ImmersiveView] Theatre environment setup complete.")
    }

    private func configureScreenEntities(in theatre: Entity) async {
        print("🖥️ [ImmersiveView] configureScreenEntities for theatre: \(theatre.name)")
        await MainActor.run {
            guard let originalScreenMesh = findModelEntity(byName: Constants.screenEntityName, in: theatre) else {
                print("❌ [ImmersiveView] Original screen mesh ('\(Constants.screenEntityName)') not found.")
                return
            }
            print("✅ [ImmersiveView] Original screen mesh located: \(originalScreenMesh.name).")

            let matte = UnlitMaterial(color: .black)
            originalScreenMesh.model?.materials = [matte]
            print("⬛ [ImmersiveView] Applied matte black material to original screen mesh.")

            let videoSurfacePlane = TheatreEntityWrapper.shared.videoPlane(for: originalScreenMesh)
            theatreEntityWrapper.screenEntity = videoSurfacePlane
            print("📺 [ImmersiveView] VideoPlane created/obtained and set in TheatreEntityWrapper.")

            Task {
                if let videoURL = appModel.selectedVideoURL,
                   !appModel.isMovieWindowOpen,
                   spaceManager.state == .open {
                    print("🎥 [ImmersiveView] Video pending for immersive view. Configuring video with sync...")
                    await configureVideoWithSync(screenEntity: videoSurfacePlane, url: videoURL)
                } else {
                    print("ℹ️ [ImmersiveView] Conditions not met for immediate video binding in configureScreenEntities: isMovieWindowOpen=\(appModel.isMovieWindowOpen), spaceState=\(spaceManager.state)")
                }
            }
        }
    }
    
    // MARK: - Lifecycle: Appear / Disappear
    private func onViewAppear() async {
        print("👋 [ImmersiveView] onViewAppear: Configuring managers and checking video state.")
        
        configureImmersiveSpaceManager()
        spaceManager.handleOpenSuccess()

        videoPlayerManager.setLightingManager(lightingManager)
        videoPlayerManager.setSpatialAudioManager(spatialAudioManager)
        theatreEntityWrapper.videoPlayerManager = videoPlayerManager
        
        if !appModel.isMovieWindowOpen, let videoURL = appModel.selectedVideoURL {
            if let videoPlane = theatreEntityWrapper.screenEntity {
                print("🎥 [ImmersiveView] onViewAppear: VideoPlane exists. Configuring video with URL: \(videoURL)")
                await configureVideoWithSync(screenEntity: videoPlane, url: videoURL)
            } else {
                print("⚠️ [ImmersiveView] onViewAppear: VideoPlane not yet available. Video setup might be pending from configureScreenEntities.")
            }
        } else {
            print("ℹ️ [ImmersiveView] onViewAppear: Conditions not met for video setup (isMovieWindowOpen=\(appModel.isMovieWindowOpen) or no videoURL).")
        }
    }
    
    private func handleCleanup() async {
        print("🧹 [ImmersiveView] handleCleanup: Starting cleanup sequence.")

        let keepPlayer = appModel.isMovieWindowOpen
        videoPlayerManager.clearAllResources(keepPlayer: keepPlayer)
        print("🧹 [ImmersiveView] VideoPlayerManager resources cleared (keepPlayer: \(keepPlayer)).")

        if let player = videoPlayerManager.player {
            let pos = player.currentTime().seconds
            let playing = player.timeControlStatus == .playing
            videoSyncService.storePlaybackSnapshot(position: pos, isPlaying: playing)
            print("📸 [ImmersiveView] Stored snapshot: pos=\(pos), playing=\(playing)")
            if playing {
                await videoSyncService.handlePlayPause(isPlaying: false)
                print("⏸️ [ImmersiveView] Paused player via VideoSyncService.")
            }
        }

        let syncCleanupLevel: CleanupLevel = keepPlayer ? .light : .full
        await videoSyncService.cleanup(level: syncCleanupLevel)
        print("🧹 [ImmersiveView] VideoSyncService cleanup called with level: \(syncCleanupLevel).")
        
        await lightingManager.stopMovieLightingEffect()
        spatialAudioManager.cleanup()
        await theatreEntityWrapper.cleanup()
        
        print("✅ [ImmersiveView] Cleanup sequence finished.")
    }

    // MARK: - Observing isMovieWindowOpen
    private func handleMovieWindowChange(_ isMovieWindowOpen: Bool) async {
        print("🎬 [ImmersiveView] handleMovieWindowChange: isMovieWindowOpen is now \(isMovieWindowOpen)")
        if isMovieWindowOpen {
            print("⬛ [ImmersiveView] MovieWindow opened. Hiding immersive video screen.")
            if let videoPlane = theatreEntityWrapper.screenEntity {
                await MainActor.run { videoPlane.isEnabled = false }
                print("✅ [ImmersiveView] Immersive videoPlane hidden.")
            }
        } else {
            print("🎬 [ImmersiveView] MovieWindow closed. Restoring immersive video screen.")
            guard let videoPlane = theatreEntityWrapper.screenEntity else {
                print("❌ [ImmersiveView] No videoPlane found to restore. Cannot continue.")
                return
            }

            await MainActor.run { videoPlane.isEnabled = true }
            print("✅ [ImmersiveView] Immersive videoPlane made visible.")

            if let videoURL = appModel.selectedVideoURL {
                print("🎥 [ImmersiveView] Re-configuring video with sync after window close.")
                await configureVideoWithSync(screenEntity: videoPlane, url: videoURL)
            } else {
                print("ℹ️ [ImmersiveView] No video URL to configure after MovieWindow closed.")
            }
        }
    }
    
    // MARK: - Handling selectedVideoURL changes
    private func handleVideoURLChange(_ newURL: URL?) async {
        print("🎬 [ImmersiveView] handleVideoURLChange: New URL is \(newURL?.absoluteString ?? "nil")")
        guard let newURL = newURL,
              let videoPlane = theatreEntityWrapper.screenEntity,
              !appModel.isMovieWindowOpen else {
            print("ℹ️ [ImmersiveView] Conditions not met for video URL change handling.")
            return
        }
        
        print("🎥 [ImmersiveView] Refreshing immersive video on VideoPlane with new URL.")
        await configureVideoWithSync(screenEntity: videoPlane, url: newURL)
    }
    
    // MARK: - Configuring Video with Sync
    private func configureVideoWithSync(screenEntity: ModelEntity, url: URL) async {
        // --- SEMAPHORE LOCK ---
        guard !isConfiguring else {
            print("🔁 [ImmersiveView] Configuration already in progress. Skipping.")
            return
        }
        isConfiguring = true
        defer {
            isConfiguring = false
            print("✅ [ImmersiveView] configureVideoWithSync finished.")
        }

        print("🎥 [ImmersiveView] configureVideoWithSync for screen: \(screenEntity.name), URL: \(url.lastPathComponent)")

        guard let currentEvent = appModel.currentEvent else {
            handleSyncFailure("Cannot configure video without a selected event.")
            return
        }
        
        let userId = appModel.currentUserId
        guard !userId.isEmpty else {
            handleSyncFailure("User identification error. Cannot sync video.")
            return
        }
        let eventId = currentEvent.id ?? ""

        if !videoSyncService.isConfigured(for: eventId, userId: userId) {
            print("🔄 [ImmersiveView] VideoSyncService not configured. Configuring now...")
            guard await videoSyncService.configureSync(eventId: eventId, userId: userId, event: currentEvent) else {
                handleSyncFailure("Failed to configure video synchronization service.")
                return
            }
        }

        if videoSyncService.currentViewState != .immersive {
            await videoSyncService.switchToView(.immersive)
        }

        // --- FIX #2 IS HERE ---
        // Call the new async `configureVideo` and get the player back directly.
        guard let player = await videoPlayerManager.configureVideo(for: screenEntity, videoURL: url) else {
            await handleSyncFailure("Failed to prepare video for playback.")
            return
        }
        
        setupVideoEndHandler()
        await videoSyncService.startSync(with: player)
        
        if appModel.resumePlaybackAfterTransition {
            print("▶️ [ImmersiveView] Resuming playback after returning from movie window (consuming intent).")
            await videoSyncService.handlePlayPause(isPlaying: true)
            appModel.resumePlaybackAfterTransition = false
        }
    }
    
    // MARK: - Video End Handler
    private func setupVideoEndHandler() {
        videoSyncService.setupVideoEndHandler {
            Task { @MainActor in
                print("🎉 [ImmersiveView] Video end handler triggered by VideoSyncService.")
                withAnimation { self.showEndScreen = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { self.showEndScreen = false }
                }
                print("🧹 [ImmersiveView] Initiating cleanup and window dismissal after video end.")
                await self.spaceManager.initiateCleanup()
                self.dismissWindow(id: "chatWindow")
                self.dismissWindow(id: "emojiWindow")
                self.dismissWindow(id: "seatMap")
                self.dismissWindow(id: "chatSettings")
                self.dismissWindow(id: "navBar")

                let stats = await self.videoSyncService.getWatchStats()
                try? await Task.sleep(for: .milliseconds(200))
                self.openWindow(id: WindowType.exitingWindow.rawValue, value: stats)
            }
        }
    }
    
    // MARK: - Seat Position Adjustment
    private func adjustViewerPosition(for selectedSeat: Entity) async {
        guard let theatre = theatreEntityWrapper.entity else {
            print("⚠️ [ImmersiveView] Cannot adjust viewer position: theatre entity is nil.")
            return
        }
        print("🪑 [ImmersiveView] Adjusting viewer position for seat: \(selectedSeat.name)")
        await MainActor.run {
            let seatPos = selectedSeat.position(relativeTo: nil)
            let viewerTargetWorldPos = SIMD3<Float>(seatPos.x, seatPos.y + Constants.viewerHeight, seatPos.z)
            let shift = -viewerTargetWorldPos
            let newTheatrePosition = theatre.position + shift
            
            print("🪑 [ImmersiveView] Current theatre pos: \(theatre.position), Seat world pos: \(seatPos), Viewer target world pos: \(viewerTargetWorldPos), Required shift: \(shift), New theatre pos: \(newTheatrePosition)")

            withAnimation(.smooth(duration: 0.8)) {
                theatre.position = newTheatrePosition
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("🔊 [ImmersiveView] Updating speaker positions after seat adjustment.")
                self.spatialAudioManager.updateSpeakerPositions(theatre)
            }
        }
    }
    
    @MainActor
    private func handleSyncFailure(_ message: String = "Video synchronization failed.") {
        print("❌ [ImmersiveView] Sync Failure: \(message)")
        accessDeniedMessage = message
        showAccessDeniedAlert = true
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
}