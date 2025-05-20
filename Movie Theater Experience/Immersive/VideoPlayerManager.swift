//
//  VideoPlayerManager.swift // Assuming this is the correct filename
//  Movie Theater Experience
//
//  Created by Anthony Fasano on [Original Date]
//

import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation
import Combine

@available(visionOS 1.0, *) // Adjusted version based on original ImmersiveView
@MainActor // Mark the whole class to run on the Main Actor by default
class VideoPlayerManager: ObservableObject {
    // MARK: - Published Properties
    @Published var player: AVPlayer?
    @Published var isPlaybackReady: Bool = false

    // MARK: - Private Properties
    private var presentationSizeCancellable: AnyCancellable?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var videoScreenEntity: ModelEntity? // Renamed from screenEntity for clarity
    private var parentScreenEntity: ModelEntity? // Keep track of the original placeholder screen
    private var spatialAudioManager: SpatialAudioManager?
    private var lightingManager: TheatreLightingManager?
    private let theatreEntityWrapper: TheatreEntityWrapper
    private let videoSyncService: VideoSyncService

    // MARK: - Initialization
    // No need for explicit @MainActor here as the class is marked
    init(videoSyncService: VideoSyncService = .shared, theatreEntityWrapper: TheatreEntityWrapper = .shared) {
        self.videoSyncService = videoSyncService
        self.theatreEntityWrapper = theatreEntityWrapper
        print("🎬 VideoPlayerManager initialized")
    }

    // MARK: - Public Methods
    func setLightingManager(_ manager: TheatreLightingManager) {
        // Already @MainActor due to class annotation
        self.lightingManager = manager
        print("💡 Lighting manager set")
    }

    func setSpatialAudioManager(_ manager: SpatialAudioManager) {
        // Already @MainActor due to class annotation
        self.spatialAudioManager = manager
        print("🔊 Spatial audio manager set")
    }

    func setScreenVisibility(screenEntity: ModelEntity?, visible: Bool) {
        // Already @MainActor due to class annotation
        guard let screenEntity = screenEntity else {
            print("⚠️ Tried to set visibility on nil screen entity")
            return
        }

        if !visible {
            print("⬛ Replacing video material with black before hiding the screen")
            let blackMaterial = UnlitMaterial(color: .black)
            screenEntity.model?.materials = [blackMaterial] // Apply black material when hiding
        } else {
            // When making visible, restore the actual video material if possible
            restoreVideoMaterial() // Ensure video material is reapplied
        }

        screenEntity.isEnabled = visible // Hide or show screen
        print(visible ? "🎬 Immersive screen **VISIBLE**" : "⬛ Immersive screen **HIDDEN**")
    }

    func configureVideo(for placeholderScreenEntity: ModelEntity, videoURL: URL, completion: @escaping (Bool) -> Void) {
        // Already @MainActor due to class annotation
        print("=== Video Configuration Start ===")
        print("Configuring video with URL: \(videoURL)")

        clearAllResources() // Clear previous state
        self.parentScreenEntity = placeholderScreenEntity // Store the placeholder

        let playerItem = AVPlayerItem(url: videoURL)
        let newPlayer = AVPlayer(playerItem: playerItem)
        self.player = newPlayer // Set the player immediately

        // Configure asset for loading - Use a Task for async work
        Task {
            do {
                // Load duration and tracks first (can be done off main thread)
                _ = try await playerItem.asset.load(.duration)
                _ = try await playerItem.asset.load(.tracks)

                // Perform checks *before* jumping back to main actor if possible
                guard playerItem.asset.duration != .zero, !(try await playerItem.asset.load(.tracks)).isEmpty else {
                    print("❌ Invalid asset loaded (zero duration or no tracks)")
                    // Ensure completion is called on the main thread
                    await MainActor.run { completion(false) }
                    return
                }

                // Now back to the main actor for player setup and observations
                await MainActor.run {
                    // Player is already set, just configure observations
                    setupPlayerObservation(newPlayer)
                    setupRateObservation(newPlayer)

                    // Configure audio
                    spatialAudioManager?.configureAudioForVideo(player: newPlayer)

                    // Setup end of video notification
                    setupEndOfVideoObservation(playerItem)

                    // Configure video presentation (which itself runs on MainActor)
                    // Use Task since setupVideoPresentation is async
                    Task {
                        let presentationSuccess = await setupVideoPresentation(for: playerItem, on: placeholderScreenEntity)

                        if presentationSuccess {
                            // Let VideoSyncService handle playback control AFTER presentation setup
                            await videoSyncService.startSync(with: newPlayer)

                            // Apply initial sync state (seek might happen internally in startSync/continueSync)
                            // No need to seek explicitly here if startSync handles snapshot restoration
                            print("✅ Initial video configuration complete, sync started.")
                            completion(true)
                        } else {
                            print("❌ Video presentation setup failed")
                            completion(false)
                        }
                    }
                }
            } catch {
                print("❌ Error configuring video asset: \(error)")
                // Ensure completion is called on the main thread
                await MainActor.run { completion(false) }
            }
        }
    }

    // MARK: - Private: RealityKit Setup

    // Returns true on success, false on failure/invalid size
    private func setupVideoPresentation(for playerItem: AVPlayerItem, on placeholderScreenEntity: ModelEntity) async -> Bool {
        // Already @MainActor due to class annotation
        await withCheckedContinuation { continuation in
            print("📐 Starting video presentation configuration")

            // Ensure we don't set up multiple sinks
            presentationSizeCancellable?.cancel()

            presentationSizeCancellable = playerItem.publisher(for: \.presentationSize)
                .receive(on: DispatchQueue.main) // Still good practice to specify receive on main
                .filter { $0.width > 0 && $0.height > 0 } // Filter out invalid sizes early
                .first() // We only need the first valid size
                .sink(receiveCompletion: { [weak self] completion in
                    // This handles the case where the publisher completes without sending a value or errors
                    switch completion {
                    case .finished:
                        // Check if videoScreenEntity was created. If not, it means no valid size was received.
                        if self?.videoScreenEntity == nil {
                             print("⚠️ Video presentation size publisher completed without a valid size.")
                             continuation.resume(returning: false)
                        }
                        // If videoScreenEntity exists, success was already handled in receiveValue.
                    case .failure(let error):
                        print("❌ Error receiving presentation size: \(error)")
                        continuation.resume(returning: false)
                    }
                }, receiveValue: { [weak self] size in
                    guard let self = self else {
                        continuation.resume(returning: false)
                        return
                    }
                    print("📐 Received valid presentation size: \(size)")
                    let aspectRatio = Float(size.width / size.height)

                    // createVideoScreen is already @MainActor
                    self.createVideoScreen(on: placeholderScreenEntity, aspectRatio: aspectRatio)
                    continuation.resume(returning: true) // Resume continuation *after* screen created
                })
        }
    }

    private func createVideoScreen(on originalEntity: ModelEntity, aspectRatio: Float) {
        // Already @MainActor due to class annotation
        print("🖥️ Creating video screen mesh")

        guard let currentPlayer = self.player else {
            print("❌ Error: No player available for video material")
            return
        }

        // Remove existing video screen entity if it exists
        if let existingScreen = videoScreenEntity {
            print("🧹 Removing existing video screen entity")
            existingScreen.removeFromParent()
            videoScreenEntity = nil
            theatreEntityWrapper.screenEntity = nil // Clear wrapper reference too
        }

        let originalBounds = originalEntity.model?.mesh.bounds ?? RealityKit.BoundingBox()
        let screenHeight = originalBounds.extents.y
        let screenWidth = screenHeight * aspectRatio

        let screenMesh = MeshResource.generatePlane(
            width: screenWidth,
            height: screenHeight
        )

        let videoMaterial = VideoMaterial(avPlayer: currentPlayer)
        let newScreen = ModelEntity(mesh: screenMesh, materials: [videoMaterial])

        // Position the new screen relative to the placeholder's parent
        newScreen.position = originalEntity.position // Position it where the placeholder was
        newScreen.orientation = originalEntity.orientation // Match orientation

        originalEntity.parent?.addChild(newScreen) // Add to the same parent as the placeholder
        originalEntity.isEnabled = false // Hide the original placeholder

        // Store reference for easy visibility toggling and cleanup
        self.videoScreenEntity = newScreen
        theatreEntityWrapper.screenEntity = newScreen // Update wrapper

        print("✅ Video screen created and added to scene. Placeholder hidden.")
    }

    // MARK: - Private: Player Observations

    private func setupPlayerObservation(_ player: AVPlayer) {
        // Already @MainActor due to class annotation
        statusObserver?.invalidate() // Invalidate previous observer if any
        statusObserver = player.observe(\.status, options: [.new]) { [weak self] observedPlayer, _ in
            // Ensure self is available, jump to main actor explicitly for safety inside KVO
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                print("ℹ️ Player status changed: \(observedPlayer.status.rawValue)")
                switch observedPlayer.status {
                case .readyToPlay:
                    print("✅ Player is ready to play")
                    self.isPlaybackReady = true
                    await self.handlePlaybackReady() // Already @MainActor
                case .failed:
                    print("❌ Player failed: \(String(describing: observedPlayer.error))")
                    self.isPlaybackReady = false
                    // Potentially trigger cleanup or error handling
                case .unknown:
                    print("❓ Player status unknown")
                    self.isPlaybackReady = false
                @unknown default:
                    self.isPlaybackReady = false
                }
            }
        }
    }

    private func setupRateObservation(_ player: AVPlayer) {
        // Already @MainActor due to class annotation
        rateObserver?.invalidate() // Invalidate previous observer
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] observedPlayer, _ in
            // Ensure self is available, jump to main actor explicitly for safety inside KVO
            Task { @MainActor [weak self] in
                 guard let self = self else { return }
                 let isPlaying = (observedPlayer.rate != 0)
                 print("⏯️ Player rate changed. Is playing: \(isPlaying)")
                 await self.handleRateChange(isPlaying) // Already @MainActor
            }
        }
    }

    private func setupEndOfVideoObservation(_ playerItem: AVPlayerItem) {
        // Already @MainActor due to class annotation
        // Ensure we remove any existing observers first for the same notification
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem, // Observe the specific item
            queue: .main // Ensure notification is handled on main queue
        ) { [weak self] _ in
            Task { @MainActor [weak self] in // Ensure execution is on MainActor
                 guard let self = self else { return }
                 print("🏁 Video playback ended (AVPlayerItemDidPlayToEndTime)")
                 await self.handleVideoEnd() // Call the async MainActor function
            }
        }
    }

    // MARK: - Private: Player State Changes

    // Already marked @MainActor via class annotation
    private func handleRateChange(_ isPlaying: Bool) async {
        if isPlaying {
            print("✨ Starting movie lighting effect")
            await lightingManager?.startMovieLightingEffect()
            restoreVideoMaterial() // Restore material when playback starts
        } else {
            print("🛑 Stopping movie lighting effect")
            await lightingManager?.stopMovieLightingEffect()
            // Optionally replace with black when paused, or keep last frame:
            // replaceVideoScreenMaterialWithBlack()
        }
        // Inform VideoSyncService about the change
        await videoSyncService.handlePlayPause(isPlaying: isPlaying)
    }

    // Already marked @MainActor via class annotation
    private func handlePlaybackReady() async {
        // Called when player status becomes .readyToPlay
        // If the intended state (from sync service) is playing, ensure lighting starts
        if videoSyncService.isPlaying {
             await lightingManager?.startMovieLightingEffect()
        }
        // Potentially restore snapshot/sync state here if needed immediately upon readiness
        // though startSync/continueSync likely handles this already.
    }


    // MARK: - Private: Video End

    // Already marked @MainActor via class annotation
    private func handleVideoEnd() async {
        print("🔚 Handling video end sequence in VideoPlayerManager")
        await lightingManager?.stopMovieLightingEffect()
        replaceVideoScreenMaterialWithBlack() // Show black screen at the end

        // Call the central handler in VideoSyncService
        await videoSyncService.handleVideoEnd() // Use the async version
    }

    // MARK: - Material Management

    // Already marked @MainActor via class annotation
    func replaceVideoScreenMaterialWithBlack() {
        guard let videoScreen = self.videoScreenEntity else {
             print("⚠️ Cannot replace material: Video screen entity is nil.")
             return
        }
        print("⬛ Applying black material to video screen")
        let blackMaterial = UnlitMaterial(color: .black)
        videoScreen.model?.materials = [blackMaterial]
    }

    // Already marked @MainActor via class annotation
    func restoreVideoMaterial() {
        guard let videoScreen = self.videoScreenEntity, let player = self.player else {
            print("⚠️ Cannot restore material: Video screen entity or player is nil.")
            return
        }
        // Check if the current material is already a VideoMaterial
        if videoScreen.model?.materials.first is VideoMaterial {
            print("ℹ️ Video material already present, no need to restore.")
            return
        }

        print("🎬 Restoring video material to video screen")
        let videoMaterial = VideoMaterial(avPlayer: player)
        videoScreen.model?.materials = [videoMaterial]
        print("✅ Video material restored.")
    }

    // MARK: - Cleanup

    // Already marked @MainActor via class annotation
    func clearAllResources(keepPlayer: Bool = false) {
        print("🧹 Clearing video resources (keepPlayer: \(keepPlayer))")

        // Use a Task for async lighting call if needed, though likely okay here
        Task { await lightingManager?.stopMovieLightingEffect() }

        // Invalidate observers and cancellables
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        presentationSizeCancellable?.cancel()
        statusObserver = nil
        rateObserver = nil
        presentationSizeCancellable = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)


        // Remove the dynamically created video screen entity
        if let videoScreen = videoScreenEntity {
            print("🧹 Removing video screen entity from parent")
            videoScreen.removeFromParent()
            videoScreenEntity = nil
            theatreEntityWrapper.screenEntity = nil // Clear wrapper reference
        }

        // Restore visibility of the original placeholder screen if it exists
        if let placeholder = parentScreenEntity {
            placeholder.isEnabled = true
            print("ℹ️ Restored visibility of placeholder screen entity.")
        }
        parentScreenEntity = nil // Clear reference

        // Handle player cleanup
        if !keepPlayer {
            print("🛑 Pausing and releasing player.")
            player?.pause() // Ensure it's paused before releasing
            player = nil
            isPlaybackReady = false
        } else {
            print("ℹ️ Keeping player instance.")
            // Optionally pause the player even if keeping it, depending on desired behavior
            // player?.pause()
        }

        print("✅ Video resources cleared.")
    }

    // MARK: - Deinitialization
    deinit {
        // This might not run on MainActor, but the cleanup should be safe
        print("🗑️ VideoPlayerManager deinitializing")
        // Ensure cleanup happens, but avoid async calls directly in deinit
        // The `clearAllResources` might have already been called by owning views.
        // Just invalidate remaining observers as a safeguard.
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        presentationSizeCancellable?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
