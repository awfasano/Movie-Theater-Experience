import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation
import Combine

@available(visionOS 2.0, *)
struct ImmersiveView: View {
    // MARK: - Properties
    @Environment(\.openWindow) var openWindow
    @Environment(AppModel.self) private var appModel
    @ObservedObject var sharedSelection = SharedSeatSelection.shared
    @ObservedObject var theatreEntityWrapper = TheatreEntityWrapper.shared
    @StateObject private var videoPlayerManager = VideoPlayerManager()
    @StateObject private var lightingManager = TheatreLightingManager()
    @StateObject private var spatialAudioManager = SpatialAudioManager()
    
    @State private var flickerTask: Task<Void, Never>?
    @State private var videoObserver: VideoStateObserver?
    @State private var showAccessDeniedAlert: Bool = false
    @State private var accessDeniedMessage: String = ""
    
    let videoSyncService = VideoSyncService.shared
    
    // MARK: - Constants
    private enum Constants {
        static let screenEntityName = "polySurface11205_lambert184_0"
        static let surroundEntityName = "polysurface11206"
        static let viewerHeight: Float = 0
        static let viewerForwardOffset: Float = 0.0
        static let baseViewingDistance: Float = 0.0
        static let initialTheatrePosition = SIMD3<Float>(0, -1, -3)
    }
    
    // MARK: - Body
    var body: some View {
        RealityView { content in
            do {
                try await setupTheatreEnvironment(in: content)
            } catch {
                print("Failed to setup theatre environment: \(error)")
            }
        }
        .onChange(of: appModel.isMovieWindowOpen) { _, isMovieWindowOpen in
            Task { @MainActor in
                if isMovieWindowOpen {
                    videoPlayerManager.pauseVideo()
                    videoSyncService.handlePlayPause(isPlaying: false)
                } else {
                    // Only resume if we're in immersive space
                    if appModel.immersiveSpaceState == .open,
                       let theatre = theatreEntityWrapper.entity,
                       let screenEntity = findModelEntity(byName: Constants.screenEntityName, in: theatre),
                       let videoURL = appModel.selectedVideoURL {
                        await configureVideoWithSync(screenEntity: screenEntity, url: videoURL)
                    }
                }
            }
        }
        .onChange(of: sharedSelection.selectedSeatEntity) { _, newSelection in
            if let selectedSeat = newSelection {
                adjustViewerPosition(for: selectedSeat)
            }
        }
        .onChange(of: appModel.selectedVideoURL) { _, newURL in
            Task { @MainActor in
                await handleVideoURLChange(newURL)
            }
        }
        .onAppear {
            Task { @MainActor in
                await onViewAppear()
            }
        }
        .onDisappear {
            Task { @MainActor in
                cleanup()
            }
        }
        .alert("Access Denied", isPresented: $showAccessDeniedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(accessDeniedMessage)
        }
    }
    
    // MARK: - Setup Methods
    private func setupTheatreEnvironment(in content: RealityViewContent) async throws {
        let theatreEntity = try await Entity(named: "Movie", in: realityKitContentBundle)
        
        theatreEntity.position = Constants.initialTheatrePosition
        theatreEntityWrapper.entity = theatreEntity
        content.add(theatreEntity)
        
        spatialAudioManager.configureSpeakersFromTheater(theatreEntity)
        await lightingManager.configureLighting(theatreEntity: theatreEntity)
        await configureScreenEntities(in: theatreEntity)
    }
    
    private func configureScreenEntities(in theatre: Entity) async {
        guard let screenEntity = findModelEntity(byName: Constants.screenEntityName, in: theatre),
              let modelEntity = screenEntity as? ModelEntity else {
            return
        }
        
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white)
        material.roughness = 0.2
        material.metallic = 0.0
        modelEntity.model?.materials = [material]
        
        if let videoURL = appModel.selectedVideoURL,
           !appModel.isMovieWindowOpen,
           appModel.immersiveSpaceState == .open {
            await configureVideoWithSync(screenEntity: screenEntity, url: videoURL)
        }
    }
    
    // MARK: - Video Configuration
    private func configureVideoWithSync(screenEntity: ModelEntity, url: URL) async {
        print("=== Starting Video Configuration with Sync ===")
        
        // Configure video player first
        videoPlayerManager.configureVideo(for: screenEntity, videoURL: url)
        
        // Wait for video player to be ready
        while !videoPlayerManager.isPlaybackReady {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        if let currentEvent = appModel.currentEvent {
            let userId = getUserId()
            print("Configuring sync with userId: \(userId)")
            
            if videoSyncService.configureSync(
                eventId: currentEvent.id ?? "",
                userId: userId,
                event: currentEvent
            ) {
                if let player = videoPlayerManager.player {
                    print("Player available, setting up sync")
                    
                    // Remove existing observer safely
                    if let observer = videoObserver {
                        print("Removing existing observer")
                        observer.stopObserving(player)
                    }
                    
                    // Create and set new observer
                    print("Creating new video observer")
                    let observer = VideoStateObserver { [weak videoSyncService] isPlaying in
                        print("Play state changed to: \(isPlaying)")
                        videoSyncService?.handlePlayPause(isPlaying: isPlaying)
                    }
                    observer.startObserving(player)
                    videoObserver = observer
                    
                    print("Starting sync service")
                    videoSyncService.startSync(with: player)
                } else {
                    print("Error: No player available after configuration")
                }
            } else {
                print("Sync configuration failed")
                videoPlayerManager.pauseVideo()
                showAccessDeniedAlert = true
                accessDeniedMessage = "This event is not currently available for viewing."
            }
        }
    }
    
    private func logSyncStatus() {
        print("""
        === Sync Status ===
        Event ID: \(appModel.currentEvent?.id ?? "none")
        User ID: \(getUserId())
        Is Host: \(videoSyncService.isHost)
        Is Within Event Time: \(videoSyncService.isWithinEventTime)
        Video Player Ready: \(videoPlayerManager.isPlaybackReady)
        Video Playing: \(videoPlayerManager.isPlaying)
        Current Time: \(videoPlayerManager.currentTime)
        ================
        """)
    }
    
    // MARK: - Event Handlers
    private func onViewAppear() async {
        appModel.handleImmersiveSpaceTransition(to: .open)
        initializeManagers()
        
        if !appModel.isMovieWindowOpen,
           let videoURL = appModel.selectedVideoURL,
           let theatre = theatreEntityWrapper.entity,
           let screenEntity = findModelEntity(byName: Constants.screenEntityName, in: theatre) {
            await configureVideoWithSync(screenEntity: screenEntity, url: videoURL)
        }
        
        theatreEntityWrapper.videoPlayerManager = videoPlayerManager
    }
    
    private func cleanup() {
        print("=== Cleaning up ImmersiveView ===")
        
        flickerTask?.cancel()
        flickerTask = nil
        
        removeVideoObserver()
        print("Video observer removed")
        
        videoSyncService.stopSync()
        print("Sync service stopped")
        
        Task { @MainActor in
            await lightingManager.stopMovieLightingEffect()
            print("Lighting effects stopped")
        }
        
        videoPlayerManager.clearAllResources()
        print("Video player resources cleared")
        
        spatialAudioManager.cleanup()
        print("Audio manager cleaned up")
        
        appModel.handleImmersiveSpaceTransition(to: .closed)
        print("Immersive space closed")
    }
    
    private func handleVideoURLChange(_ newURL: URL?) async {
        guard let newURL = newURL,
              let theatre = theatreEntityWrapper.entity,
              let screenEntity = findModelEntity(byName: Constants.screenEntityName, in: theatre),
              !appModel.isMovieWindowOpen,
              appModel.immersiveSpaceState == .open else {
            return
        }
        
        await configureVideoWithSync(screenEntity: screenEntity, url: newURL)
    }
    
    // MARK: - Position Management
    private func adjustViewerPosition(for selectedSeat: Entity) {
        guard let theatre = theatreEntityWrapper.entity else { return }
        
        let seatWorldPosition = selectedSeat.position(relativeTo: nil)
        let viewerPosition = SIMD3<Float>(
            seatWorldPosition.x,
            seatWorldPosition.y + Constants.viewerHeight,
            seatWorldPosition.z
        )
        
        let theatreAdjustment = SIMD3<Float>(
            -viewerPosition.x,
            -viewerPosition.y,
            -viewerPosition.z
        )
        
        withAnimation(.smooth(duration: 0.8)) {
            theatre.position += theatreAdjustment
        }
        
        // Update audio after movement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            spatialAudioManager.updateSpeakerPositions(theatre)
        }
    }
    
    // MARK: - Helper Methods
    private func initializeManagers() {
        videoPlayerManager.setSpatialAudioManager(spatialAudioManager)
        
        flickerTask?.cancel()
        flickerTask = nil
    }
    
    private func findModelEntity(byName name: String, in entity: Entity) -> ModelEntity? {
        if let modelEntity = entity as? ModelEntity, entity.name.contains(name) {
            return modelEntity
        }
        
        for child in entity.children {
            if let found = findModelEntity(byName: name, in: child) {
                return found
            }
        }
        
        return nil
    }
    
    private func removeVideoObserver() {
        if let observer = videoObserver,
           let player = videoPlayerManager.player {
            observer.stopObserving(player)
        }
        videoObserver = nil
    }
    
    private func getUserId() -> String {
        UserDefaults.standard.string(forKey: "userId") ?? UUID().uuidString
    }
}
