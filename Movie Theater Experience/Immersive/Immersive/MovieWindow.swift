import SwiftUI
// import RealityFoundation // Keep if used by other parts of AppModel or services
import AVKit
import AVFoundation

struct MovieWindow: View {

    // MARK: ‑‑ Environment
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow // Keep if used for other window interactions
    // @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace // Not directly used here
    // @Environment(\.openWindow) private var openWindow // Not directly used here for opening other windows

    // MARK: ‑‑ State
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var showAccessDeniedAlert = false
    @State private var accessDeniedMessage = ""
    // @State private var rateObserver: NSKeyValueObservation? // Not directly used in provided snippet, can be removed if not needed
    // videoDuration is now sourced from videoSyncService.currentVideoDuration for the SeekSliderView

    // MARK: ‑‑ Services
    // private let spaceManager = ImmersiveSpaceManager.shared // Not directly used in this view's logic
    // Use @State for @Observable shared instances to ensure the view observes changes
    @State var videoSyncService = VideoSyncService.shared

    // MARK: ‑‑ Body
    var body: some View {
        ZStack {
            // main video or placeholder
            Group {
                if let player = player { // Ensure we use the @State player
                    VideoPlayerView(player: player, videoGravity: .resizeAspect)
                        .overlay(Color.black.opacity(0.000)) // allow tap‑through
                } else {
                    ProgressView("Loading…")
                        .progressViewStyle(.circular)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: player != nil)

            // Controls Overlay including SeekSliderView, PlayPauseButton, and Sync Button
            VStack {
                Spacer() // Pushes controls to the bottom

                // Show controls only if player exists and duration is known
                if player != nil && videoSyncService.currentVideoDuration > 0 {
                    HStack(spacing: 12) { // Added spacing for better layout
                        PlayPauseButton()
                            .padding(.trailing, 0) // Adjusted padding

                        SeekSliderView(duration: videoSyncService.currentVideoDuration)
                        
                        // --- NEW CODE START ---
                        Text("\(videoSyncService.currentTime.formatted()) / \(videoSyncService.currentVideoDuration.formatted())")
                            .font(.caption.monospacedDigit()) // Monospaced font prevents the text from shifting
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 120, alignment: .center) // Give it a consistent width
                            .padding(.horizontal, 4)
                        // --- NEW CODE END ---

                        // Sync with Host Button
                        if !videoSyncService.isHost {
                            Button {
                                Task {
                                    print("🎬 [MovieWindow] Sync with Host button tapped.")
                                    await videoSyncService.forceSyncToHost()
                                }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                    .font(.title2)
                            }
                            .help("Sync with Host")
                            .padding(.leading, 0) // Adjusted padding
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 315) // 16:9 base
        .padding() // Overall padding for the window content
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 8)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(appModel.currentEvent?.title ?? "Now Playing")
                    .font(.headline)
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    Task {
                        await handleWindowClose() // Use a dedicated close handler
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .help("Close Movie Window")
            }
        }
        .task { await setupVideo() }
        .onDisappear {
            // This onDisappear might be too broad if the window is just covered.
            // Consider if cleanup should only happen on explicit close.
            // For now, assuming onDisappear means the window is going away.
            // If MovieWindow can be covered by other windows without closing,
            // this cleanup might be premature.
            // Task { await handleCleanup() } // Original cleanup
        }
        .alert("Access Denied", isPresented: $showAccessDeniedAlert) {
            Button("OK", role: .cancel) {
                Task {
                    await handleWindowClose() // Also use dedicated close handler here
                }
            }
        } message: { Text(accessDeniedMessage) }
    }

    // MARK: ‑‑ Initial setup
    private func setupVideo() async {
        print("🎬 [MovieWindow] setupVideo started")

        guard
            let videoURL = appModel.selectedVideoURL,
            let event = appModel.currentEvent
        else {
            presentAccessDenied("Missing video URL or event.")
            return
        }

        let newPlayer = AVPlayer(url: videoURL)
        // Do not pause immediately here; let VideoSyncService control it after sync.
        // newPlayer.pause()
        
        // Update the @State player on the MainActor
        await MainActor.run {
            self.player = newPlayer
            self.isLoading = true // Keep true until sync service confirms state
        }


        let uid = appModel.currentUserId // NEW WAY - Use the consistent User ID from AppModel
        let eid = event.id ?? ""

        let alreadyConfigured = videoSyncService.isConfigured(for: eid, userId: uid)
        if !alreadyConfigured {
            print("🔄 [MovieWindow] Configuring sync service for event \(eid) with AppModel User ID: \(uid)...") // Added log for clarity
            guard await videoSyncService.configureSync(eventId: eid,
                                                   userId: uid, // Use the 'uid' from AppModel
                                                   event: event)
            else {
                // This is the required else block for the guard statement
                presentAccessDenied("This event isn’t available right now (sync config failed).")
                return // Exit the setupVideo method if configureSync fails
            }
            print("✅ [MovieWindow] Sync configured for event \(eid)") // This line will only be reached if configureSync succeeds
            try? await Task.sleep(for: .milliseconds(300)) // Let listeners settle
        } else {
            print("ℹ️ [MovieWindow] Sync already configured for event \(eid) – re‑using session")
        }
        
        // VideoSyncService.startSync will handle player readiness and duration.
        // No need to manually load duration here if startSync does it.
        // VideoSyncService.continueSync will set videoSyncService.currentVideoDuration.

        // Ensure VideoSyncService is aware of the current view context
        // This should happen *before* startSync if switchToView manages snapshots correctly.
        // If MovieWindow is opening, AppModel.isMovieWindowOpen should be true.
        // The logic in AppModel or the view that opens MovieWindow should call switchToView.
        // For robustness, we can call it here if not already in the correct state.
        if videoSyncService.currentViewState != .movieWindow {
            print("🎬 [MovieWindow] Explicitly switching VideoSyncService to .movieWindow state.")
            await videoSyncService.switchToView(.movieWindow) // This will store snapshot and pause previous player
        }

        // Pass the player to VideoSyncService to manage.
        // startSync should handle player readiness checks and then call continueSync.
        await videoSyncService.startSync(with: newPlayer)

        // isLoading should be set to false after startSync completes and player state is known.
        // VideoSyncService's isPlaying will determine if player.play() is called.
        // The visual loading state can be tied to player readiness or a flag in VideoSyncService.
        // For simplicity, let's assume startSync handles the initial play/pause.
        
        // Check if player became ready and duration was loaded by VideoSyncService
        // This check is more for the UI state than for re-doing work.
        if newPlayer.status == .readyToPlay && videoSyncService.currentVideoDuration > 0 {
             print("✅ [MovieWindow] Player ready and duration known after startSync.")
        } else if newPlayer.status == .failed || (newPlayer.currentItem != nil && newPlayer.currentItem!.status == .failed) {
             print("❌ [MovieWindow] Player or item failed after startSync attempt.")
             let errorDesc = newPlayer.error?.localizedDescription ?? newPlayer.currentItem?.error?.localizedDescription ?? "Unknown player error"
            presentAccessDenied("Cannot play this video (\(errorDesc)).")
             return // Critical failure
        } else {
             print("⏳ [MovieWindow] Player might still be loading or duration pending after startSync call. UI will update via VideoSyncService state.")
        }

        // The actual play/pause will be handled by VideoSyncService based on snapshot or host state.
        // No explicit newPlayer.play() or newPlayer.pause() here after startSync.

        await MainActor.run { // Ensure UI updates are on main actor
            isLoading = false
        }
        print("✅ [MovieWindow] setupVideo finished. Player state managed by VideoSyncService.")
    }

    private func handleWindowClose() async {
        print("🎬 [MovieWindow] handleWindowClose called.")
        
        // 1. Set the intent to resume playback in the immersive view.
        appModel.resumePlaybackAfterTransition = true

        // 2. Inform the AppModel that the window is closing.
        appModel.isMovieWindowOpen = false

        // 3. Tell the sync service to prepare for the immersive view.
        if videoSyncService.currentViewState == .movieWindow {
            print("🎬 [MovieWindow] Closing window, switching sync service back to .immersive state.")
            await videoSyncService.switchToView(.immersive)
        }
        
        // Perform local player cleanup
        if let player = self.player {
            player.pause()
        }
        await MainActor.run {
            self.player = nil
        }

        // Dismiss the window
        dismiss()
        print("✅ [MovieWindow] Window close handling complete.")
    }

    // MARK: ‑‑ Helpers
    @MainActor
    private func presentAccessDenied(_ reason: String) {
        print("❌ [MovieWindow] Access Denied: \(reason)")
        accessDeniedMessage = reason
        showAccessDeniedAlert = true
        isLoading = false // Stop loading indicator on error
    }
}

// Supporting Views (VideoPlayerView, PlayerView) remain unchanged.
// Make sure SeekSliderView.swift and ThinTrackSliderControl.swift are in your project.

// Helper extension for CMTime
extension CMTime {
    var secondsIfFinite: Double? {
        let s = CMTimeGetSeconds(self)
        return s.isFinite && !s.isNaN ? s : nil
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
