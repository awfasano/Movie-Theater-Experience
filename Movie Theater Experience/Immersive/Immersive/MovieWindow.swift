import SwiftUI
import RealityFoundation
import AVKit
import AVFoundation

struct MovieWindow: View {
    // MARK: - Environment
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) var openWindow
    
    // MARK: - State
    @State private var player: AVPlayer?
    @State private var showAccessDeniedAlert = false
    @State private var accessDeniedMessage = ""
    @State private var rateObserver: NSKeyValueObservation?
    
    // MARK: - Services
    private let spaceManager = ImmersiveSpaceManager.shared
    private let videoSyncService = VideoSyncService.shared
    
    var body: some View {
        VStack {
            if let player = player {
                VideoPlayerView(player: player, videoGravity: .resizeAspect)
                    .edgesIgnoringSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Loading video...")
            }
        }
        .task {
            await setupVideo()
        }
        .onDisappear {
            handleOnDisappear()
        }
        .alert("Access Denied", isPresented: $showAccessDeniedAlert) {
            Button("OK", role: .cancel) {
                handleCleanup()
                dismiss()
            }
        } message: {
            Text(accessDeniedMessage)
        }
    }
    
    // MARK: - Setup
    // In MovieWindow.swift
    private func setupVideo() async {
        print("🎬 Setting up video in MovieWindow")
        
        guard let videoURL = appModel.selectedVideoURL,
              let event = appModel.currentEvent else {
            print("❌ Missing video URL or event")
            handleCleanup()
            dismiss()
            return
        }
        
        // Create new AVPlayer
        let newPlayer = AVPlayer(url: videoURL)
        
        // Ensure player is initially paused
        newPlayer.pause()
        self.player = newPlayer
        
        // Configure sync first
        if videoSyncService.configureSync(
            eventId: event.id ?? "",
            userId: getDeviceId(),
            event: event
        ) {
            print("✅ Video sync configured")
            
            // IMPORTANT: Wait for player to be ready
            while newPlayer.status != .readyToPlay {
                print("⏳ Waiting for player to be ready...")
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            print("✅ Player ready to play")
            
            // Get current sync time and seek to it
            let syncTime = videoSyncService.currentTime
            print("⏱️ Seeking to sync time: \(syncTime)")
            
            // Use accurate seeking and wait for it to complete
            await newPlayer.seek(to: CMTime(seconds: syncTime, preferredTimescale: 1000),
                               toleranceBefore: .zero,
                               toleranceAfter: .zero)
            print("✅ Seek completed")
            
            // Setup end handler
            setupVideoEndHandler()
            
            // Start sync
            videoSyncService.startSync(with: newPlayer)
            
            // Match current playstate
            let shouldPlay = videoSyncService.isPlaying
            print("🎮 Current sync play state: \(shouldPlay)")
            
            if shouldPlay {
                print("▶️ Starting playback")
                newPlayer.play()
            } else {
                print("⏸️ Ensuring paused")
                newPlayer.pause()
            }
            
            print("✅ MovieWindow video setup complete")
        } else {
            print("❌ Sync configuration failed")
            showAccessDenied()
        }
    }

    // Add this to help debug what's happening with the player
    private func addDebugObservations() {
        guard let player = player else { return }
        
        // Observe timeControlStatus
        let statusObserver = player.observe(\.timeControlStatus) { player, _ in
            print("🎮 Player timeControlStatus: \(player.timeControlStatus.rawValue)")
            switch player.timeControlStatus {
            case .playing:
                print("▶️ Player is playing")
            case .paused:
                print("⏸️ Player is paused")
            case .waitingToPlayAtSpecifiedRate:
                print("⏳ Player is waiting to play")
            @unknown default:
                break
            }
        }
        // Store statusObserver if needed
    }
    
    private func setupRateObservation(_ player: AVPlayer) {
        rateObserver = player.observe(\.rate, options: [.new]) { [weak videoSyncService] player, _ in
            let isPlaying = (player.rate != 0)
            videoSyncService?.handlePlayPause(isPlaying: isPlaying)
        }
    }
    
    private func setupVideoEndHandler() {
        videoSyncService.setupVideoEndHandler {
            Task { @MainActor in
                await handleVideoEnd()
            }
        }
    }
    
    // MARK: - Cleanup
    private func handleCleanup() {
        print("🧹 MovieWindow cleanup")
        
        // Create snapshot before any cleanup
        if let player = player {
            let position = player.currentTime().seconds
            let isPlaying = player.rate != 0
            print("📸 Creating final snapshot - position: \(position), playing: \(isPlaying)")
        }
        
        videoSyncService.switchToView(.immersive)
        
        // Don't cleanup videoSyncService here
        videoSyncService.cleanup(level: .light) 
        
        player?.pause()
        player = nil
        appModel.isMovieWindowOpen = false
    }
    
    private func handleOnDisappear() {
        print("🪟 MovieWindow onDisappear called")
        handleCleanup()
        appModel.isMovieWindowOpen = false
    }
    
    private func handleVideoEnd() async {
        print("🎬 Handling video end in MovieWindow...")

        // Call the global video end handler in VideoSyncService
        await VideoSyncService.shared.handleVideoEnd()
    }
    
    private func dismissAllWindows() {
        print("🪟 Dismissing all content windows")
        let ids = ["chatWindow", "emojiWindow", "movieWindow", "seatMap", "navBar"]
        for wId in ids {
            dismissWindow(id: wId)
        }
    }
    
    // MARK: - Helpers
    private func showAccessDenied() {
        showAccessDeniedAlert = true
        accessDeniedMessage = "This event is not currently available for viewing."
        handleCleanup()
        dismiss()
    }

    private func getDeviceId() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
}

// Supporting Views remain unchanged
struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity
    
    func makeUIView(context: Context) -> UIView {
        PlayerView(player: player, videoGravity: videoGravity)
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as! PlayerView).playerLayer.videoGravity = videoGravity
    }
}

class PlayerView: UIView {
    let playerLayer: AVPlayerLayer
    
    init(player: AVPlayer, videoGravity: AVLayerVideoGravity) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = videoGravity
        super.init(frame: .zero)
        layer.addSublayer(playerLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
