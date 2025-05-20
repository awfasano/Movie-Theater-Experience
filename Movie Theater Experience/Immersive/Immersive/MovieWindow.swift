import SwiftUI
import RealityFoundation
import AVKit
import AVFoundation

struct MovieWindow: View {

    // MARK: ‑‑ Environment
    @Environment(AppModel.self)         private var appModel
    @Environment(\.dismiss)             private var dismiss
    @Environment(\.dismissWindow)       private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow)          private var openWindow

    // MARK: ‑‑ State
    @State private var player: AVPlayer?
    @State private var isLoading            = true
    @State private var showAccessDeniedAlert = false
    @State private var accessDeniedMessage   = ""
    @State private var rateObserver: NSKeyValueObservation?

    // MARK: ‑‑ Services
    private let spaceManager    = ImmersiveSpaceManager.shared
    private let videoSyncService = VideoSyncService.shared

    // MARK: ‑‑ Body
    var body: some View {
        ZStack {
            // main video or placeholder
            Group {
                if let player {
                    VideoPlayerView(player: player,
                                    videoGravity: .resizeAspect)
                        .overlay(Color.black.opacity(0.001)) // allow tap‑through
                } else {
                    ProgressView("Loading…")
                        .progressViewStyle(.circular)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: player != nil)
        }
        .frame(minWidth: 560, minHeight: 315)               // 16:9 base
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 8)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(appModel.currentEvent?.title ?? "Now Playing")
                    .font(.headline)
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    Task { await handleCleanup() ; dismiss() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .help("Close")
            }
        }
        .task { await setupVideo() }
        .onDisappear {
            // onDisappear must not call async directly
            Task { await handleCleanup() }
        }
        .alert("Access Denied", isPresented: $showAccessDeniedAlert) {
            Button("OK", role: .cancel) {
                Task { await handleCleanup() ; dismiss() }
            }
        } message: { Text(accessDeniedMessage) }
    }

    // MARK: ‑‑ Initial setup
    private func setupVideo() async {
        print("🎬 [MovieWindow] setupVideo started")

        // 0️⃣ Sanity‑check inputs
        guard
            let videoURL = appModel.selectedVideoURL,
            let event    = appModel.currentEvent
        else {
            await presentAccessDenied("Missing video URL or event.")
            return
        }

        // 1️⃣ Create the AVPlayer (initially paused)
        let newPlayer = AVPlayer(url: videoURL)
        newPlayer.pause()
        player    = newPlayer          // show the player
        isLoading = true

        // 2️⃣ Configure (or reuse) the VideoSyncService
        let uid = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let eid = event.id ?? ""

        let alreadyConfigured = videoSyncService.isConfigured(for: eid, userId: uid)
        if !alreadyConfigured {
            print("🔄 Configuring sync service …")
            guard await videoSyncService.configureSync(eventId: eid,
                                                 userId:  uid,
                                                 event:   event)
            else {
                await presentAccessDenied("This event isn’t available right now.")
                return
            }
            print("✅ Sync configured")
            try? await Task.sleep(for: .milliseconds(300))   // let listeners settle
        } else {
            print("ℹ️ Sync already configured – re‑using session")
        }

        // 3️⃣ Wait for the player to be ready
        while newPlayer.status == .unknown {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard newPlayer.status == .readyToPlay else {
            await presentAccessDenied("Cannot play this video.")
            return
        }
        print("✅ Player ready")

        // 4️⃣ Seek to the current sync position
        let syncPos = videoSyncService.currentTime
        await newPlayer.seek(to: CMTime(seconds: syncPos, preferredTimescale: 1000),
                             toleranceBefore: .zero,
                             toleranceAfter:  .zero)
        print("⏱️ Sought to \(String(format: "%.2f", syncPos)) s")

        // 5️⃣ Register video‑end handler *once*
        videoSyncService.setupVideoEndHandler {
            Task { await handleVideoEnd() }
        }

        // 6️⃣ Hand the player to the sync service
        await videoSyncService.startSync(with: newPlayer)

        // 7️⃣ Match the play/pause state from Firestore
        if videoSyncService.isPlaying {
            print("▶️ Starting playback")
            newPlayer.play()
        } else {
            newPlayer.pause()
        }

        // 8️⃣ Done — hide loading placeholder
        withAnimation { isLoading = false }
        print("✅ [MovieWindow] setupVideo finished")
    }


    // MARK: ‑‑ Cleanup
    private func handleCleanup() async {
        // snapshot
        if let player {
            let pos = player.currentTime().seconds
            let play = player.timeControlStatus == .playing
            videoSyncService.storePlaybackSnapshot(position: pos, isPlaying: play)
        }

        // tidy
        await videoSyncService.cleanup(level: .light)
        player?.pause()
        player = nil
        appModel.isMovieWindowOpen = false
    }

    private func handleVideoEnd() async {
        await videoSyncService.handleVideoEnd()
    }

    // MARK: ‑‑ Helpers
    @MainActor
    private func presentAccessDenied(_ reason: String) {
        accessDeniedMessage = reason
        showAccessDeniedAlert = true
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
