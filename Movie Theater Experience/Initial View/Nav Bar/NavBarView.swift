import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation
import Combine

struct NavBarView: View {
    // MARK: - Environment
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject var windowManager: WindowManager

    // MARK: - State
    @AppStorage("showEmojis") private var showEmojis = true
    @State var videoSyncService = VideoSyncService.shared // Observe VideoSyncService

    // MARK: - Services
    // Ensure this line is present and ImmersiveSpaceManager is correctly defined and accessible
    private let spaceManager = ImmersiveSpaceManager.shared

    // State for displaying formatted time
    @State private var currentTimeFormatted: String = "00:00"
    @State private var totalDurationFormatted: String = "00:00"

    var body: some View {
        HStack(spacing: 15) {
            // Left-aligned buttons
            chatButton
            emojiButton
            emojiVisibilityButton
            movieButton
            seatMapButton

            // Media Controls - Conditionally shown
            if appModel.selectedVideoURL != nil && videoSyncService.currentVideoDuration > 0 {
                HStack(spacing: 10) {
                    PlayPauseButton()

                    Text(currentTimeFormatted)
                        .font(.caption)
                        .monospacedDigit()
                        .frame(minWidth: 45, alignment: .trailing)

                    SeekSliderView(duration: videoSyncService.currentVideoDuration)
                        .frame(width: 200)

                    Text(totalDurationFormatted)
                        .font(.caption)
                        .monospacedDigit()
                        .frame(minWidth: 45, alignment: .leading)
                }
                .padding(.horizontal, 10)
            }

            // Sync with Host Button
            if !videoSyncService.isHost && appModel.selectedVideoURL != nil {
                syncWithHostButton
            }

            Spacer()

            chatSettingsButton
            exitButton
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.9))
        .cornerRadius(10)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if appModel.selectedVideoURL != nil {
                self.currentTimeFormatted = formatTime(videoSyncService.currentTime)
                if videoSyncService.currentVideoDuration > 0 {
                    let newFormattedTotalDuration = formatTime(videoSyncService.currentVideoDuration)
                    if self.totalDurationFormatted != newFormattedTotalDuration {
                        self.totalDurationFormatted = newFormattedTotalDuration
                    }
                } else if totalDurationFormatted != "00:00" {
                    self.totalDurationFormatted = "00:00"
                }
            } else {
                if currentTimeFormatted != "00:00" { self.currentTimeFormatted = "00:00" }
                if totalDurationFormatted != "00:00" { self.totalDurationFormatted = "00:00" }
            }
        }
        .onChange(of: videoSyncService.currentVideoDuration) { _, newDuration in
            self.totalDurationFormatted = formatTime(newDuration)
        }
        .onChange(of: appModel.selectedVideoURL) { _, newURL in
            if newURL == nil {
                self.currentTimeFormatted = "00:00"
                self.totalDurationFormatted = "00:00"
            } else {
                 self.totalDurationFormatted = formatTime(videoSyncService.currentVideoDuration)
            }
        }
    }

    // MARK: - Time Formatting Helper
    private func formatTime(_ time: Double) -> String {
        let validTime = time.isFinite ? time : 0.0
        let seconds = Int(validTime)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    // MARK: - Chat Button
    private var chatButton: some View {
        Button {
            if !windowManager.isWindowOpen(.chat) {
                openWindow(id: WindowType.chat.rawValue)
                windowManager.windowOpened(.chat)
            }
        } label: {
            Image(systemName: "message.fill")
                .resizable()
                .frame(width: 28, height: 28)
        }
        .help("Open Chat")
    }

    // MARK: - Emoji Button
    private var emojiButton: some View {
        Button {
            if !windowManager.isWindowOpen(.emoji) {
                openWindow(id: WindowType.emoji.rawValue)
                windowManager.windowOpened(.emoji)
            }
        } label: {
            Image(systemName: "face.smiling.fill")
                .resizable()
                .frame(width: 28, height: 28)
        }
        .help("Open Emoji Tray")
        // Corrected: Fully qualify the enum case
        .disabled(spaceManager.state != ImmersiveSpaceState.open)
    }

    // MARK: - Emoji Visibility Button
    private var emojiVisibilityButton: some View {
        Button {
            showEmojis.toggle()
            TheatreEntityWrapper.shared.setEmojiVisibility(showEmojis)
        } label: {
            Image(systemName: showEmojis ? "eye.fill" : "eye.slash.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "face.smiling.fill")
                        .resizable()
                        .frame(width: 14, height: 14)
                        .offset(x: 7, y: 7)
                )
        }
        .help(showEmojis ? "Hide Emojis" : "Show Emojis")
    }

    // MARK: - Movie Window Button
    private var movieButton: some View {
        Button {
            if appModel.selectedVideoURL != nil {
                Task {
                    if appModel.isMovieWindowOpen {
                        print("🎬 Movie button: Movie window open, switching to immersive.")
                        await videoSyncService.switchToView(.immersive)
                        appModel.isMovieWindowOpen = false
                        appModel.resumePlaybackAfterTransition = true

                        dismissWindow(id: WindowType.movie.rawValue)
                        windowManager.windowClosed(.movie)
                        // Corrected: Fully qualify the enum case
                        if spaceManager.state != ImmersiveSpaceState.open {
                             _ = await ImmersiveSpaceManager.shared.openImmersiveSpace()
                        }
                    } else {
                        print("🎬 Movie button: Movie window not open, switching to movie window.")
                        await videoSyncService.switchToView(.movieWindow)
                        appModel.isMovieWindowOpen = true
                        openWindow(id: WindowType.movie.rawValue)
                        windowManager.windowOpened(.movie)
                    }
                }
            }
        } label: {
            Image(systemName: appModel.isMovieWindowOpen ? "arrow.down.right.and.arrow.up.left.rectangle.fill" : "rectangle.on.rectangle")
                .resizable()
                .frame(width: 28, height: 28)
        }
        .help(appModel.isMovieWindowOpen ? "Close Movie Window (Return to Immersive)" : "Open Movie in Window")
        .disabled(appModel.selectedVideoURL == nil)
    }

    // MARK: - Seat Map Button
    private var seatMapButton: some View {
        Button {
            if !windowManager.isWindowOpen(.seatMap) {
                openWindow(id: WindowType.seatMap.rawValue)
                windowManager.windowOpened(.seatMap)
            }
        } label: {
            Image(systemName: "chair.fill")
                .resizable()
                .frame(width: 28, height: 28)
        }
        .help("Open Seat Map")
    }

    // MARK: - Sync with Host Button
    private var syncWithHostButton: some View {
        Button {
            Task {
                print("🎬 [NavBarView] Sync with Host button tapped.")
                await videoSyncService.forceSyncToHost()
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .resizable()
                .frame(width: 28, height: 28)
        }
        .help("Sync with Host")
    }

    // MARK: - Chat Settings Button
    private var chatSettingsButton: some View {
        Button {
            if !windowManager.isWindowOpen(.chatSettings) {
                openWindow(id: WindowType.chatSettings.rawValue)
                windowManager.windowOpened(.chatSettings)
            }
        } label: {
            Image(systemName: "paintbrush.fill")
                .resizable()
                .frame(width: 28, height: 28)
        }
        .help("Open Chat Settings")
    }

    // MARK: - Full Exit Button
    private var exitButton: some View {
        Button {
            Task {
                await handleExit()
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundStyle(.red)
        }
        .help("Exit Experience")
    }

    // MARK: - Full Exit Handler
    private func handleExit() async {
        print("📤 Full exit requested from NavBar")
        let stats = await videoSyncService.getWatchStats()
        await videoSyncService.cleanup(level: .full)
        // Ensure spaceManager is accessible here. If it's a struct property, it will be.
        await spaceManager.initiateCleanup()

        for windowType in WindowType.allCases where windowType != .exitingWindow {
            if windowManager.isWindowOpen(windowType) {
                print("🚪 Closing window: \(windowType.rawValue)")
                dismissWindow(id: windowType.rawValue)
                windowManager.windowClosed(windowType)
            }
        }
        
        try? await Task.sleep(for: .milliseconds(200))

        if !windowManager.isWindowOpen(.exitingWindow) {
            print("🚪 Opening exiting window with stats.")
            openWindow(id: WindowType.exitingWindow.rawValue, value: stats)
            windowManager.windowOpened(.exitingWindow)
        }
        print("✅ NavBar exit sequence complete.")
    }
}
