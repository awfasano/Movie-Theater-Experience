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
    private let videoSyncService: VideoSyncService
    
    // MARK: - Initialization
    init(videoSyncService: VideoSyncService = .shared) {
        self.videoSyncService = videoSyncService
        print("VideoPlayerManager initialized")
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
    
    func configureVideo(for screenEntity: ModelEntity, videoURL: URL) {
        print("=== Video Configuration Start ===")
        print("Configuring video with URL: \(videoURL)")
        
        clearAllResources()
        self.screenEntity = screenEntity
        
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        
        // Immediately seek to current sync time
        let currentTime = videoSyncService.currentTime
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 1000))
        
        // Configure observations
        setupPlayerObservation(player)
        setupRateObservation(player)
        
        self.player = player
        spatialAudioManager?.configureAudioForVideo(player: player)
        
        // Setup end of video notification
        setupEndOfVideoObservation(playerItem)
        
        // Configure video presentation
        configureVideoPresentation(for: playerItem, on: screenEntity)
        
        // Let VideoSyncService handle playback control
        videoSyncService.startSync(with: player)
        
        // Match current play state
        if videoSyncService.isPlayingState {
            player.play()
        } else {
            player.pause()
        }
        
        print("Initial video configuration complete")
    }
    
    func clearAllResources() {
        print("Clearing all video resources")
        
        // Make sure we stop lighting on the main actor
        Task {
            await lightingManager?.stopMovieLightingEffect()
        }
        
        // Remove observers
        statusObserver?.invalidate()
        statusObserver = nil
        
        rateObserver?.invalidate()
        rateObserver = nil
        
        presentationSizeCancellable?.cancel()
        presentationSizeCancellable = nil
        
        // Remove video screen
        if let videoScreen = videoScreenEntity {
            videoScreen.removeFromParent()
            videoScreenEntity = nil
        }
        
        // Reset state
        isPlaybackReady = false
        player = nil
        
        print("All resources cleared")
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
        
        presentationSizeCancellable = playerItem.publisher(for: \.presentationSize)
            .receive(on: DispatchQueue.main)
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
                
                self.createVideoScreen(on: screenEntity, aspectRatio: aspectRatio)
            }
    }
    
    private func createVideoScreen(on originalEntity: ModelEntity, aspectRatio: Float) {
        print("Creating video screen")
        
        guard let currentPlayer = self.player else {
            print("Error: No player available for video material")
            return
        }
        
        // Safely do RealityKit entity manipulation on main actor
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
            self.videoScreenEntity = newScreen
            
            print("Video screen created and added to scene")
        }
    }
    
    // MARK: - Private: Video End
    
    private func handleVideoEnd() {
        Task {
            // This might also need the main actor if it calls RealityKit
            await lightingManager?.stopMovieLightingEffect()
            replaceVideoScreenMaterialWithBlack()
        }
        videoSyncService.handleVideoEnd()
    }
    
    // MARK: - Material Management
    
    // *** FIX ***: Because we call it from handleRateChange (which is now @MainActor),
    // these can be plain (no concurrency). But you can also mark them @MainActor to be explicit.
    func replaceVideoScreenMaterialWithBlack() {
        guard let videoScreenEntity = videoScreenEntity else { return }
        let blackMaterial = UnlitMaterial(color: .black)
        videoScreenEntity.model?.materials = [blackMaterial]
    }
    
    func restoreVideoMaterial() {
        guard let videoScreenEntity = videoScreenEntity,
              let player = player else { return }
        
        let videoMaterial = VideoMaterial(avPlayer: player)
        videoScreenEntity.model?.materials = [videoMaterial]
    }
    
    // MARK: - Deinitialization
    
    deinit {
        print("VideoPlayerManager deinitializing")
        clearAllResources()
        NotificationCenter.default.removeObserver(self)
    }
}
