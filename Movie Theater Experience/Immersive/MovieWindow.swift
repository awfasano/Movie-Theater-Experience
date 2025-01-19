import SwiftUI
import RealityFoundation
import AVKit
import AVFoundation

struct MovieWindow: View {
    // MARK: - Properties
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var showAccessDeniedAlert = false
    @State private var accessDeniedMessage = ""
    @State private var videoObserver: VideoStateObserver?
    
    let videoSyncService = VideoSyncService.shared

    
    // MARK: - Body
    @available(visionOS 2.0, *)
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
            cleanup()
            
            // If in immersive view, reconfigure the theatre screen
            if appModel.immersiveSpaceState == .open,
               let videoURL = appModel.selectedVideoURL,
               let theatre = TheatreEntityWrapper.shared.entity,
               let screenEntity = findModelEntity(byName: "polySurface11205_lambert184_0", in: theatre),
               let videoManager = TheatreEntityWrapper.shared.videoPlayerManager {
                videoManager.configureVideo(for: screenEntity, videoURL: videoURL)
            }
        }
        .alert("Access Denied", isPresented: $showAccessDeniedAlert) {
            Button("OK", role: .cancel) {
                cleanup()
                dismiss()
            }
        } message: {
            Text(accessDeniedMessage)
        }
    }
    
    // MARK: - Setup Methods
    private func setupVideo() async {
        print("=== Setting up video playback in MovieWindow ===")
        
        guard let videoURL = appModel.selectedVideoURL,
              let event = appModel.currentEvent else {
            print("Missing video URL or event")
            cleanup()
            dismiss()
            return
        }
        
        print("Creating player with URL: \(videoURL)")
        let player = AVPlayer(url: videoURL)
        self.player = player
        
        // Configure sync service
        let userId = getUserId()
        print("Configuring sync with userId: \(userId)")
        
        if videoSyncService.configureSync(
            eventId: event.id ?? "",
            userId: userId,
            event: event
        ) {
            print("Sync service configured successfully")
            
            // Setup video observer
            let observer = VideoStateObserver { [weak videoSyncService] isPlaying in
                print("Play state changed to: \(isPlaying)")
                videoSyncService?.handlePlayPause(isPlaying: isPlaying)
            }
            observer.startObserving(player)
            videoObserver = observer
            
            // Start sync and playback
            print("Starting sync service")
            videoSyncService.startSync(with: player)
            
            // Setup end of video notification
            setupEndOfVideoNotification(for: player)
            
        } else {
            print("Sync configuration failed")
            showAccessDeniedAlert = true
            accessDeniedMessage = "This event is not currently available for viewing."
            cleanup()
            dismiss()
        }
    }
    
    private func cleanup() {
        print("=== Cleaning up MovieWindow ===")
        
        removeVideoObserver()
        print("Video observer removed")
        
        videoSyncService.stopSync()
        print("Sync service stopped")
        
        player?.pause()
        player = nil
        print("Player cleared")
        
        appModel.handleMovieWindowClosure()
        print("Movie window closed")
    }
    
    private func logSyncStatus() {
        print("""
        === Sync Status ===
        Event ID: \(appModel.currentEvent?.id ?? "none")
        User ID: \(getUserId())
        Is Host: \(videoSyncService.isHost)
        Is Within Event Time: \(videoSyncService.isWithinEventTime)
        Player Rate: \(player?.rate ?? 0)
        Current Time: \(player?.currentTime().seconds ?? 0)
        ================
        """)
    }
    
    private func setupEndOfVideoNotification(for player: AVPlayer) {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak videoSyncService] _ in
            videoSyncService?.handlePlayPause(isPlaying: false)
        }
    }
    
    // MARK: - Helper Methods
    private func getUserId() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
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
           let player = player {
            observer.stopObserving(player)
        }
        videoObserver = nil
    }
}

// MARK: - Supporting Views
struct VideoPlayerView: UIViewRepresentable {
    var player: AVPlayer
    var videoGravity: AVLayerVideoGravity
    
    func makeUIView(context: Context) -> UIView {
        return PlayerView(player: player, videoGravity: videoGravity)
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as! PlayerView).playerLayer.videoGravity = videoGravity
    }
}

class PlayerView: UIView {
    var playerLayer: AVPlayerLayer
    
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
