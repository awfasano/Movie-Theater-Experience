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
        // Wait for any ongoing cleanup
        while spaceManager.isCleaningUp {
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
        
        try? await Task.sleep(for: .milliseconds(50))

        await MainActor.run {
            spatialAudioManager.configureSpeakersFromTheater(theatreEntity)
        }
        await lightingManager.configureLighting(theatreEntity: theatreEntity)

        await configureScreenEntities(in: theatreEntity)
    }

    private func configureScreenEntities(in theatre: Entity) async {
        await MainActor.run {
            guard
                let originalScreenMesh = findModelEntity(byName: Constants.screenEntityName, in: theatre)
            else {
                print("❌ Original screen mesh ('\(Constants.screenEntityName)') not found in theatre entity.")
                return
            }

            let matte = UnlitMaterial(color: .black)
            originalScreenMesh.model?.materials = [matte]

            let videoSurfacePlane = TheatreEntityWrapper.shared.videoPlane(for: originalScreenMesh)
            theatreEntityWrapper.screenEntity = videoSurfacePlane

            Task {
                if let videoURL = appModel.selectedVideoURL,
                   !appModel.isMovieWindowOpen,
                   case .open = spaceManager.state {

                    await configureVideoWithSync(screenEntity: videoSurfacePlane, url: videoURL)
                }
            }
        }
    }


    
    // MARK: - Lifecycle: Appear / Disappear
    private func onViewAppear() async {
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
        
        spaceManager.handleOpenSuccess()

        videoPlayerManager.setSpatialAudioManager(spatialAudioManager)
        theatreEntityWrapper.videoPlayerManager = videoPlayerManager

        if !appModel.isMovieWindowOpen,
           let videoURL = appModel.selectedVideoURL,
           let videoPlane = theatreEntityWrapper.screenEntity {
            await configureVideoWithSync(screenEntity: videoPlane, url: videoURL)
        }
    }
    
    private func handleCleanup() async {
        let keepPlayer = appModel.isMovieWindowOpen
        videoPlayerManager.clearAllResources(keepPlayer: keepPlayer)

        if let player = videoPlayerManager.player {
            let pos = player.currentTime().seconds
            let playing = player.timeControlStatus == .playing
            videoSyncService.storePlaybackSnapshot(position: pos, isPlaying: playing)

            if playing {
                await videoSyncService.handlePlayPause(isPlaying: false)
            }
        }

        await videoSyncService.cleanup(level: keepPlayer ? .light : .full)
        await lightingManager.stopMovieLightingEffect()
        spatialAudioManager.cleanup()
        await theatreEntityWrapper.cleanup()
        await spaceManager.initiateCleanup()
    }


    // MARK: - Observing isMovieWindowOpen
    private func handleMovieWindowChange(_ isMovieWindowOpen: Bool) async {
        if isMovieWindowOpen {
            if let videoPlane = theatreEntityWrapper.screenEntity {
                await MainActor.run {
                    videoPlane.isEnabled = false
                }
            }
            return
        }

        guard let videoPlane = theatreEntityWrapper.screenEntity else {
            if let theatre = theatreEntityWrapper.entity {
                await configureScreenEntities(in: theatre)
            }
            return
        }

        guard let videoURL = appModel.selectedVideoURL else {
            return
        }

        await MainActor.run {
            videoPlane.isEnabled = true
        }

        await configureVideoWithSync(screenEntity: videoPlane, url: videoURL)

        if let snapshot = videoSyncService.currentSnapshot {
            guard let player = videoPlayerManager.player else {
                print("❌ No player found after restoring screen entity")
                return
            }

            await player.seek(to: CMTime(seconds: snapshot.position, preferredTimescale: 1000))

            if snapshot.isPlaying {
                player.play()
            } else {
                player.pause()
            }
        }
    }
    
    // MARK: - Handling selectedVideoURL changes
    private func handleVideoURLChange(_ newURL: URL?) async {
        guard let newURL = newURL,
              let videoPlane = theatreEntityWrapper.screenEntity,
              !appModel.isMovieWindowOpen else {
            return
        }

        await configureVideoWithSync(screenEntity: videoPlane, url: newURL)
    }
    
    // MARK: - Configuring Video with Sync
    private func configureVideoWithSync(
        screenEntity: ModelEntity,
        url: URL
    ) async {
        guard let currentEvent = appModel.currentEvent else {
            print("❌ No current event found – aborting video load")
            return
        }
        let eventId = currentEvent.id ?? ""
        let userId  = getUserId()

        if !videoSyncService.isConfigured(for: eventId, userId: userId) {
            guard await videoSyncService.configureSync(
                    eventId: eventId,
                    userId:  userId,
                    event:   currentEvent)
            else {
                print("❌ Sync configuration failed")
                handleSyncFailure()
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }

        let videoConfigured = await withCheckedContinuation { continuation in
            Task { @MainActor in
                videoPlayerManager.configureVideo(
                    for: screenEntity,
                    videoURL: url
                ) { success in
                    if !success {
                        print("❌ Video material configuration failed")
                    }
                    continuation.resume(returning: success)
                }
            }
        }

        guard videoConfigured else { return }

        var attempts = 0
        while !videoPlayerManager.isPlaybackReady && attempts < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }
        guard videoPlayerManager.isPlaybackReady else {
            print("❌ Player readiness timeout")
            return
        }

        setupVideoEndHandler()

        if let player = videoPlayerManager.player {
            await videoSyncService.startSync(with: player)
        }

    }
    
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
