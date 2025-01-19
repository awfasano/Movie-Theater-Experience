import Foundation
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
    @Published var currentTime: Double = 0.0
    @Published var isPlaying: Bool = false
    
    // MARK: - Private Properties
    private var presentationSizeCancellable: AnyCancellable?
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    
    private var screenEntity: ModelEntity?
    private var videoScreenEntity: ModelEntity?
    private var spatialAudioManager: SpatialAudioManager?
    private var lightingManager: TheatreLightingManager?
    
    // MARK: - Initialization
    init() {
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
        
        // Configure player status observation
        setupPlayerObservation(player)
        
        // Configure time observation
        setupTimeObservation(player)
        
        self.player = player
        spatialAudioManager?.configureAudioForVideo(player: player)
        
        // Setup end of video notification
        setupEndOfVideoObservation(playerItem)
        
        // Configure video presentation
        configureVideoPresentation(for: playerItem, on: screenEntity)
        
        print("Initial video configuration complete")
    }
    
    func startPlayback() {
        print("Starting video playback")
        guard let player = player, isPlaybackReady else {
            print("Cannot start playback: Player not ready")
            return
        }
        
        Task {
            await lightingManager?.startMovieLightingEffect()
            player.play()
            isPlaying = true
            print("Playback started - player rate: \(player.rate)")
        }
    }
    
    func pauseVideo() {
        print("Pausing video")
        player?.pause()
        isPlaying = false
        replaceVideoScreenMaterialWithBlack()
        Task {
            await lightingManager?.stopMovieLightingEffect()
        }
    }
    
    func resumeVideo() {
        print("Resuming video")
        guard isPlaybackReady else {
            print("Cannot resume: Playback not ready")
            return
        }
        
        restoreVideoMaterial()
        Task {
            await lightingManager?.startMovieLightingEffect()
            player?.play()
            isPlaying = true
        }
    }
    
    func seekTo(time: CMTime, completion: ((Bool) -> Void)? = nil) {
        print("Seeking to time: \(time.seconds)")
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            print("Seek completed: \(finished)")
            completion?(finished)
        }
    }
    
    func clearAllResources() {
        print("Clearing all video resources")
        
        Task {
            await lightingManager?.stopMovieLightingEffect()
        }
        
        if let timeObserverToken = timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        
        statusObserver?.invalidate()
        statusObserver = nil
        
        rateObserver?.invalidate()
        rateObserver = nil
        
        presentationSizeCancellable?.cancel()
        presentationSizeCancellable = nil
        
        player?.pause()
        player = nil
        
        if let videoScreen = videoScreenEntity {
            videoScreen.removeFromParent()
            videoScreenEntity = nil
        }
        
        isPlaybackReady = false
        isPlaying = false
        currentTime = 0.0
        
        print("All resources cleared")
    }
    
    // MARK: - Private Methods
    private func setupPlayerObservation(_ player: AVPlayer) {
        // Observe player status
        statusObserver = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            print("Player status changed: \(player.status.rawValue)")
            DispatchQueue.main.async {
                switch player.status {
                case .readyToPlay:
                    print("Player is ready to play")
                    self?.isPlaybackReady = true
                case .failed:
                    print("Player failed: \(String(describing: player.error))")
                    self?.isPlaybackReady = false
                case .unknown:
                    print("Player status unknown")
                    self?.isPlaybackReady = false
                @unknown default:
                    break
                }
            }
        }
        
        // Observe player rate
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isPlaying = player.rate != 0
            }
        }
    }
    
    private func setupTimeObservation(_ player: AVPlayer) {
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 0.5, preferredTimescale: timeScale)
        
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
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
        let originalBounds = originalEntity.model?.mesh.bounds ?? RealityKit.BoundingBox()
        let screenHeight = originalBounds.extents.y
        let screenWidth = screenHeight * aspectRatio
        
        let screenMesh = MeshResource.generatePlane(
            width: screenWidth,
            height: screenHeight
        )
        
        guard let player = self.player else {
            print("Error: No player available for video material")
            return
        }
        
        let videoMaterial = VideoMaterial(avPlayer: player)
        let newScreen = ModelEntity(mesh: screenMesh, materials: [videoMaterial])
        
        newScreen.position = originalBounds.center
        newScreen.orientation = originalEntity.orientation
        
        originalEntity.parent?.addChild(newScreen)
        self.videoScreenEntity = newScreen
        print("Video screen created and added to scene")
    }
    
    private func handleVideoEnd() {
        isPlaying = false
        Task {
            await lightingManager?.stopMovieLightingEffect()
        }
    }
    
    private func restoreVideoMaterial() {
        guard let videoScreenEntity = videoScreenEntity,
              let player = player else { return }
        
        let videoMaterial = VideoMaterial(avPlayer: player)
        videoScreenEntity.model?.materials = [videoMaterial]
    }
    
    private func replaceVideoScreenMaterialWithBlack() {
        guard let videoScreenEntity = videoScreenEntity else { return }
        let blackMaterial = UnlitMaterial(color: .black)
        videoScreenEntity.model?.materials = [blackMaterial]
    }
    
    // MARK: - Deinitialization
    deinit {
        print("VideoPlayerManager deinitializing")
        clearAllResources()
    }
}
