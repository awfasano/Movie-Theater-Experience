//
//  VideoPlayerManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on [Original Date]
//

import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation
import Combine

@available(visionOS 1.0, *)
@MainActor // Mark the whole class to run on the Main Actor by default
class VideoPlayerManager: ObservableObject {
    // MARK: - Published Properties
    @Published var player: AVPlayer?
    @Published var isPlaybackReady: Bool = false

    // MARK: - Private Properties
    private var presentationSizeCancellable: AnyCancellable?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var videoScreenEntity: ModelEntity?
    private var parentScreenEntity: ModelEntity?
    private var spatialAudioManager: SpatialAudioManager?
    private var lightingManager: TheatreLightingManager?
    private let theatreEntityWrapper: TheatreEntityWrapper
    // Note: No videoSyncService property needed here anymore.

    // MARK: - Initialization
    init(theatreEntityWrapper: TheatreEntityWrapper = .shared) {
        self.theatreEntityWrapper = theatreEntityWrapper
        print("🎬 VideoPlayerManager initialized")
    }

    // MARK: - Public Methods
    func setLightingManager(_ manager: TheatreLightingManager) {
        self.lightingManager = manager
        print("💡 Lighting manager set")
    }

    func setSpatialAudioManager(_ manager: SpatialAudioManager) {
        self.spatialAudioManager = manager
        print("🔊 Spatial audio manager set")
    }
    
    // This is a new, simplified configuration method.
    // It returns the created player to the caller (ImmersiveView),
    // giving it control over when to start the sync.
    // In VideoPlayerManager.swift

    // This is the new, safer version of your configureVideo function.
    func configureVideo(for placeholderScreenEntity: ModelEntity, videoURL: URL) async -> AVPlayer? {
        print("=== VideoPlayerManager: Visual Configuration Start ===")
        print("Configuring with URL: \(videoURL)")

        // --- THIS LINE WAS REMOVED ---
        // clearAllResources() // Do NOT clear everything at the start of configuration.

        // If the player exists and is for the same URL, we might not need to do anything.
        // For simplicity now, we'll still create a new player but avoid the destructive full cleanup.
        // Invalidate old observers before creating new ones.
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        presentationSizeCancellable?.cancel()
        
        self.parentScreenEntity = placeholderScreenEntity

        let playerItem = AVPlayerItem(url: videoURL)
        
        // Pre-load asset properties
        do {
            _ = try await playerItem.asset.load(.duration, .tracks)
        } catch {
            print("❌ Error pre-loading asset properties: \(error)")
            return nil
        }

        let newPlayer = AVPlayer(playerItem: playerItem)
        self.player = newPlayer
        
        setupPlayerObservation(newPlayer)
        setupRateObservation(newPlayer)
        setupEndOfVideoObservation(playerItem)
        spatialAudioManager?.configureAudioForVideo(player: newPlayer)

        let presentationSuccess = await setupVideoPresentation(for: playerItem, on: placeholderScreenEntity)
        
        if presentationSuccess {
            print("✅ VideoPlayerManager visual configuration complete. Ready for sync.")
            return newPlayer
        } else {
            print("❌ Video presentation setup failed.")
            clearAllResources() // Clear resources if setup fails.
            return nil
        }
    }

    // MARK: - Private: RealityKit Setup
    private func setupVideoPresentation(for playerItem: AVPlayerItem, on placeholderScreenEntity: ModelEntity) async -> Bool {
        return await withCheckedContinuation { continuation in
            print("📐 Starting video presentation configuration")
            presentationSizeCancellable?.cancel()

            presentationSizeCancellable = playerItem.publisher(for: \.presentationSize)
                .filter { $0.width > 0 && $0.height > 0 }
                .first()
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("❌ Error receiving presentation size: \(error)")
                            continuation.resume(returning: false)
                        }
                    },
                    receiveValue: { [weak self] size in
                        guard let self = self else {
                            continuation.resume(returning: false)
                            return
                        }
                        self.createVideoScreen(on: placeholderScreenEntity, aspectRatio: Float(size.width / size.height))
                        continuation.resume(returning: true)
                    }
                )
        }
    }
    
    // In VideoPlayerManager.swift

    private func createVideoScreen(on originalEntity: ModelEntity, aspectRatio: Float) {
        guard let currentPlayer = self.player else { return }

        // --- START OF FIX ---

        // 1. Capture the parent entity immediately. This is the crucial change.
        // We must get a reference to the parent *before* we risk removing the originalEntity from it.
        guard let parent = originalEntity.parent else {
            print("❌ Cannot create video screen: The original entity has no parent in the scene graph.")
            return
        }

        // 2. Now that we have a safe reference to the parent, we can clean up the previous screen.
        if let existingScreen = self.videoScreenEntity {
            existingScreen.removeFromParent()
        }
        
        // --- END OF FIX ---

        // The rest of your function logic is correct.
        let originalBounds = originalEntity.model?.mesh.bounds ?? .init()
        let screenHeight = originalBounds.extents.y
        let screenWidth = screenHeight * aspectRatio
        let screenMesh = MeshResource.generatePlane(width: screenWidth, height: screenHeight)
        let videoMaterial = VideoMaterial(avPlayer: currentPlayer)
        let newScreen = ModelEntity(mesh: screenMesh, materials: [videoMaterial])

        newScreen.position = originalEntity.position
        newScreen.orientation = originalEntity.orientation

        // 3. Use the safely captured 'parent' to add the new screen to the scene.
        parent.addChild(newScreen)
        
        // 4. Hide the placeholder entity that was passed in.
        originalEntity.isEnabled = false

        // 5. Update the internal and shared references to point to the newly created screen.
        self.videoScreenEntity = newScreen
        theatreEntityWrapper.screenEntity = newScreen
        print("✅ Video screen created and added to scene.")
    }

    // MARK: - Private: Player Observations

    private func setupPlayerObservation(_ player: AVPlayer) {
        statusObserver?.invalidate()
        statusObserver = player.observe(\.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.isPlaybackReady = (self?.player?.status == .readyToPlay)
            }
        }
    }

    // --- FIX #1: The Rate Change Handler is now safe ---
    private func setupRateObservation(_ player: AVPlayer) {
        rateObserver?.invalidate()
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let isPlaying = (observedPlayer.rate != 0)
                print("⏯️ Player rate changed. Is playing: \(isPlaying)")
                // The only job of this observer is to update local visuals.
                await self.handleRateChange(isPlaying)
            }
        }
    }
    
    // --- FIX #2: The handleRateChange function NO LONGER calls the sync service ---
    private func handleRateChange(_ isPlaying: Bool) async {
        if isPlaying {
            await lightingManager?.startMovieLightingEffect()
        } else {
            await lightingManager?.stopMovieLightingEffect()
        }
        // The line that called videoSyncService.handlePlayPause has been DELETED.
    }
    
    private func setupEndOfVideoObservation(_ playerItem: AVPlayerItem) {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            Task { await self?.handleVideoEnd() }
        }
    }

    // MARK: - Private: Video End and Cleanup
    private func handleVideoEnd() async {
        await lightingManager?.stopMovieLightingEffect()
        replaceVideoScreenMaterialWithBlack()
        await VideoSyncService.shared.handleVideoEnd()
    }

    func replaceVideoScreenMaterialWithBlack() {
        guard let videoScreen = self.videoScreenEntity else { return }
        videoScreen.model?.materials = [UnlitMaterial(color: .black)]
    }

    func clearAllResources(keepPlayer: Bool = false) {
        print("🧹 Clearing video resources (keepPlayer: \(keepPlayer))")

        Task { await lightingManager?.stopMovieLightingEffect() }

        statusObserver?.invalidate()
        rateObserver?.invalidate()
        presentationSizeCancellable?.cancel()
        NotificationCenter.default.removeObserver(self)

        if let videoScreen = videoScreenEntity {
            videoScreen.removeFromParent()
            self.videoScreenEntity = nil
            theatreEntityWrapper.screenEntity = nil
        }
        if let placeholder = parentScreenEntity {
            placeholder.isEnabled = true
        }
        parentScreenEntity = nil

        if !keepPlayer {
            player?.pause()
            player = nil
            isPlaybackReady = false
        }
    }
    
    deinit {
        print("🗑️ VideoPlayerManager deinitializing. Primary cleanup should occur in ImmersiveView.handleCleanup().")

        // Perform minimal, thread-safe observer invalidation as a final safeguard.
        // These operations are generally safe to call from any thread.
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        presentationSizeCancellable?.cancel()
        NotificationCenter.default.removeObserver(self) // This is thread-safe

        // IMPORTANT: Do NOT call methods here that require the MainActor,
        // such as UI updates, RealityKit operations, or methods that modify
        // @Published properties without explicit MainActor dispatch (which isn't safe in deinit).
        // The main call to clearAllResources() is handled by the owning view (ImmersiveView).
        print("🗑️ VideoPlayerManager deinit: Basic observer invalidation complete as safeguard.")
    }
}
