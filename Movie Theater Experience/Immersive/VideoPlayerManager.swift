//
//  Untitled.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/28/25.
//

import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation
import Combine

@available(visionOS 2.0, *)
class VideoPlayerManager: ObservableObject {
    // MARK: - Published Properties
    @Published var player: AVPlayer?
    @Published var isPlaybackReady: Bool = false
    
    // MARK: - Private Properties
    private var presentationSizeCancellable: AnyCancellable?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var screenEntity: ModelEntity?
    private var videoScreenEntity: ModelEntity?
    private var spatialAudioManager: SpatialAudioManager?
    private var lightingManager: TheatreLightingManager?
    private let theatreEntityWrapper: TheatreEntityWrapper
    private let videoSyncService: VideoSyncService

    
    
    
    // MARK: - Initialization
    init(videoSyncService: VideoSyncService = .shared, theatreEntityWrapper: TheatreEntityWrapper = .shared) {
        self.videoSyncService = videoSyncService
        self.theatreEntityWrapper = theatreEntityWrapper
        print("🎬 VideoPlayerManager initialized")
    }
    
    // MARK: - Public Methods
    func setLightingManager(_ manager: TheatreLightingManager) {
        self.lightingManager = manager
        print("Lighting manager set")
    }
    
    func setSpatialAudioManager(_ manager: SpatialAudioManager) {
        self.spatialAudioManager = manager
        print("Spatial audio manager set")
    }
    
    func setScreenVisibility(screenEntity: ModelEntity?, visible: Bool) async {
        guard let screenEntity = screenEntity else { return }

        await MainActor.run {
            if !visible {
                print("⬛ Replacing video material with black before hiding the screen")
                let blackMaterial = UnlitMaterial(color: .black)
                screenEntity.model?.materials = [blackMaterial]  // Apply black material when hiding
            }
            
            screenEntity.isEnabled = visible  // Hide or show screen
            print(visible ? "🎬 Immersive screen **VISIBLE**" : "⬛ Immersive screen **HIDDEN**")
        }
    }


    
    private func setupVideoPresentation(for playerItem: AVPlayerItem, on screenEntity: ModelEntity) async -> Bool {
        return await withCheckedContinuation { continuation in
            print("Starting video presentation configuration")
            
            var hasCompletedSetup = false
            
            presentationSizeCancellable = playerItem.publisher(for: \.presentationSize)
                .receive(on: DispatchQueue.main)
                .removeDuplicates()
                .sink { [weak self] size in
                    print("Received presentation size: \(size)")
                    
                    guard let self = self else {
                        if !hasCompletedSetup {
                            hasCompletedSetup = true
                            continuation.resume(returning: false)
                        }
                        return
                    }
                    
                    guard size.width > 0, size.height > 0 else {
                        if size.width == 0 && size.height == 0 {
                            // Skip invalid size
                            return
                        }
                        if !hasCompletedSetup {
                            hasCompletedSetup = true
                            continuation.resume(returning: false)
                        }
                        return
                    }
                    
                    let aspectRatio = Float(size.width / size.height)
                    Task { @MainActor in
                        self.createVideoScreen(on: screenEntity, aspectRatio: aspectRatio)
                        if !hasCompletedSetup {
                            hasCompletedSetup = true
                            continuation.resume(returning: true)
                        }
                    }
                }
        }
    }

    
    
    func configureVideo(for screenEntity: ModelEntity, videoURL: URL, completion: @escaping (Bool) -> Void) {
        print("=== Video Configuration Start ===")
        print("Configuring video with URL: \(videoURL)")
        
        clearAllResources()
        self.screenEntity = screenEntity
        
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        
        // Configure asset for loading
        let asset = playerItem.asset
        Task {
            do {
                // Load duration and tracks first
                let duration = try await asset.load(.duration)
                let tracks = try await asset.load(.tracks)
                
                guard duration != .zero, !tracks.isEmpty else {
                    print("❌ Invalid asset loaded")
                    completion(false)
                    return
                }
                
                await MainActor.run {
                    // Now configure the player after asset is loaded
                    self.player = player
                    
                    // Configure observations after player is set
                    setupPlayerObservation(player)
                    setupRateObservation(player)
                    
                    // Configure audio after player is ready
                    spatialAudioManager?.configureAudioForVideo(player: player)
                    
                    // Setup end of video notification
                    setupEndOfVideoObservation(playerItem)
                    
                    // Configure video presentation with completion
                    Task {
                        let presentationSuccess = await setupVideoPresentation(for: playerItem, on: screenEntity)
                        
                        if presentationSuccess {
                            // Let VideoSyncService handle playback control
                            videoSyncService.startSync(with: player)
                            
                            // Seek to current sync time
                            let currentTime = videoSyncService.currentTime
                            await player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 1000))
                            
                            // Match current play state
                            if videoSyncService.isPlaying {
                                player.play()
                            }
                            
                            print("✅ Initial video configuration complete")
                            completion(true)
                        } else {
                            print("❌ Video presentation setup failed")
                            completion(false)
                        }
                    }
                }
            } catch {
                print("❌ Error configuring video: \(error)")
                completion(false)
            }
        }
    }
    
    func clearAllResources(keepPlayer: Bool = false) {
        print("🧹 Clearing video resources (keepPlayer: \(keepPlayer))")

        Task { await lightingManager?.stopMovieLightingEffect() }

        // Remove observers
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        statusObserver = nil
        rateObserver = nil
        presentationSizeCancellable?.cancel()
        presentationSizeCancellable = nil

        // If we should clear the player completely, remove it
        if !keepPlayer {
            player = nil
        }

        // Remove the video screen entity if it exists
        if let videoScreen = videoScreenEntity {
            videoScreen.removeFromParent()
            videoScreenEntity = nil
        }

        print("✅ Video resources cleared")
    }

    
    // MARK: - Private: Player Observations
    
    private func setupPlayerObservation(_ player: AVPlayer) {
        statusObserver = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            print("Player status changed: \(player.status.rawValue)")
            
            // Jump onto main actor for RealityKit & SwiftUI
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch player.status {
                case .readyToPlay:
                    print("Player is ready to play")
                    self.isPlaybackReady = true
                    await self.handlePlaybackReady()
                case .failed:
                    print("Player failed: \(String(describing: player.error))")
                    self.isPlaybackReady = false
                case .unknown:
                    print("Player status unknown")
                    self.isPlaybackReady = false
                @unknown default:
                    break
                }
            }
        }
    }
    
    // *** FIX ***: Use a Task { @MainActor in ... } block
    private func setupRateObservation(_ player: AVPlayer) {
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                let isPlaying = (player.rate != 0)
                await self.handleRateChange(isPlaying) // call the new async MainActor function
            }
        }
    }
    
    // MARK: - Private: Player State Changes
    
    // *** FIX ***: Mark as @MainActor + async so we can await lighting safely
    @MainActor
    private func handleRateChange(_ isPlaying: Bool) async {
        if isPlaying {
            await lightingManager?.startMovieLightingEffect()
            restoreVideoMaterial()  // safe on main actor
        } else {
            await lightingManager?.stopMovieLightingEffect()
            replaceVideoScreenMaterialWithBlack() // safe on main actor
        }
    }
    
    // *** FIX ***: Also mark as @MainActor + async if you are awaiting
    @MainActor
    private func handlePlaybackReady() async {
        if let player = player, player.rate != 0 {
            await lightingManager?.startMovieLightingEffect()
        }
    }
    
    private func setupEndOfVideoObservation(_ playerItem: AVPlayerItem) {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            print("Video playback ended")
            self?.handleVideoEnd()
        }
    }
    
    // MARK: - Private: RealityKit Setup
    
    private func configureVideoPresentation(for playerItem: AVPlayerItem, on screenEntity: ModelEntity) {
        print("Starting video presentation configuration")
        
        // Cancel any existing subscription
        presentationSizeCancellable?.cancel()
        
        presentationSizeCancellable = playerItem.publisher(for: \.presentationSize)
            .receive(on: DispatchQueue.main)
            .removeDuplicates() // Add this to prevent duplicate processing
            .sink { [weak self] size in
                print("Received presentation size: \(size)")
                
                guard let self = self,
                      size.width > 0,
                      size.height > 0 else {
                    print("Invalid presentation size or self reference")
                    return
                }
                
                let aspectRatio = Float(size.width / size.height)
                print("Creating video screen with aspect ratio: \(aspectRatio)")
                
                // Remove existing screen first
                if let existingScreen = self.videoScreenEntity {
                    print("🧹 Removing existing video screen")
                    existingScreen.removeFromParent()
                    self.videoScreenEntity = nil
                }
                
                self.createVideoScreen(on: screenEntity, aspectRatio: aspectRatio)
            }
    }
    
    private func createVideoScreen(on originalEntity: ModelEntity, aspectRatio: Float) {
        print("Creating video screen")

        guard let currentPlayer = self.player else {
            print("Error: No player available for video material")
            return
        }

        Task { @MainActor in
            let originalBounds = originalEntity.model?.mesh.bounds ?? RealityKit.BoundingBox()
            let screenHeight = originalBounds.extents.y
            let screenWidth = screenHeight * aspectRatio

            let screenMesh = MeshResource.generatePlane(
                width: screenWidth,
                height: screenHeight
            )

            let videoMaterial = VideoMaterial(avPlayer: currentPlayer)
            let newScreen = ModelEntity(mesh: screenMesh, materials: [videoMaterial])

            newScreen.position = originalBounds.center
            newScreen.orientation = originalEntity.orientation

            originalEntity.parent?.addChild(newScreen)

            // Store reference for easy visibility toggling
            theatreEntityWrapper.screenEntity = newScreen
            self.videoScreenEntity = newScreen

            print("✅ Video screen created and added to scene")
        }
    }

    
    // MARK: - Private: Video End
    
    private func handleVideoEnd() {
        Task {
            // This might also need the main actor if it calls RealityKit
            await lightingManager?.stopMovieLightingEffect()
            await replaceVideoScreenMaterialWithBlack()
        }
        videoSyncService.handleVideoEnd()
    }
    
    // MARK: - Material Management
    
    // *** FIX ***: Because we call it from handleRateChange (which is now @MainActor),
    // these can be plain (no concurrency). But you can also mark them @MainActor to be explicit.
    @MainActor
    func replaceVideoScreenMaterialWithBlack() {
        guard let videoScreenEntity = videoScreenEntity else { return }
        print("⬛ Replacing video material with black")
        let blackMaterial = UnlitMaterial(color: .black)
        videoScreenEntity.model?.materials = [blackMaterial]
    }
    
    @MainActor
    func restoreVideoMaterial() {
        print("🎬 Attempting to restore video material")
        guard let videoScreenEntity = videoScreenEntity,
              let player = player else {
            print("❌ Cannot restore video material - missing entity or player")
            return
        }
        print("🎬 Creating new video material")
        let videoMaterial = VideoMaterial(avPlayer: player)
        print("🎬 Applying video material to screen")
        videoScreenEntity.model?.materials = [videoMaterial]
        print("✅ Video material restored")
    }
    
    // MARK: - Deinitialization
    
    deinit {
        print("VideoPlayerManager deinitializing")
        clearAllResources()
        NotificationCenter.default.removeObserver(self)
    }
}
