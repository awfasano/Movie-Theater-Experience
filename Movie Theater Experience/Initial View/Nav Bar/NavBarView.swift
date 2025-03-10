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
    @State private var showMovieEndAlert = false

    // MARK: - Services
    private let spaceManager = ImmersiveSpaceManager.shared
    let videoSyncService = VideoSyncService.shared

    var body: some View {
        HStack(spacing: 40) {
            chatButton
            emojiButton
            emojiVisibilityButton
            movieButton
            seatMapButton
            exitButton
            chatSettingsButton
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.9))
        .cornerRadius(10)
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
                .frame(width: 30, height: 30)
        }
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
                .frame(width: 30, height: 30)
        }
        .disabled(spaceManager.state != .open)
    }

    // MARK: - Emoji Visibility Button
    private var emojiVisibilityButton: some View {
        Button {
            showEmojis.toggle()
            TheatreEntityWrapper.shared.setEmojiVisibility(showEmojis)
        } label: {
            Image(systemName: showEmojis ? "eye.fill" : "eye.slash.fill")
                .resizable()
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "face.smiling.fill")
                        .resizable()
                        .frame(width: 15, height: 15)
                        .offset(x: 8, y: 8)
                )
        }
    }

    // MARK: - Movie Window Button
    private var movieButton: some View {
        Button {
            if let _ = appModel.selectedVideoURL, !windowManager.isWindowOpen(.movie) {
                Task {
                    videoSyncService.switchToView(.movieWindow)
                    if case .open = spaceManager.state {
                        TheatreEntityWrapper.shared.videoPlayerManager?.clearAllResources()
                    }
                    appModel.isMovieWindowOpen = true
                    openWindow(id: WindowType.movie.rawValue)
                    windowManager.windowOpened(.movie)
                }
            }
        } label: {
            Image(systemName: "rectangle.on.rectangle")
                .resizable()
                .frame(width: 30, height: 30)
        }
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
                .frame(width: 30, height: 30)
        }
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
                .frame(width: 30, height: 30)
        }
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
                .frame(width: 30, height: 30)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Full Exit Handler
    private func handleExit() async {
        print("📤 Full exit: initiating host election and cleaning up.")
        // Get watch stats before cleanup
        let stats = VideoSyncService.shared.getWatchStats()
        
        // Cleanup sync and space
        await VideoSyncService.shared.initiateHostElection()
        await spaceManager.initiateCleanup()
        
        // Dismiss all active windows
        dismissWindow(id: "chatWindow")
        dismissWindow(id: "emojiWindow")
        dismissWindow(id: "movieWindow")
        dismissWindow(id: "seatMap")
        dismissWindow(id: "chatSettings")
        dismissWindow(id: "navBar")
        
        // Show stats window after a small delay to ensure clean transitions
        try? await Task.sleep(for: .milliseconds(100))
        if !windowManager.isWindowOpen(.exitingWindow) {
            openWindow(id: WindowType.exitingWindow.rawValue, value: stats)
            windowManager.windowOpened(.exitingWindow)
        }
        print("✅ Cleanup complete; exit window shown.")
    }
}
