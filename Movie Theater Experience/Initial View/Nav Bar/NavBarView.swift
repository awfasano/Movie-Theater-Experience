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
        .accessibilityLabel("Open chat")
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
        .accessibilityLabel("Open emoji reactions")
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
        .accessibilityLabel(showEmojis ? "Hide emoji reactions" : "Show emoji reactions")
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
        .accessibilityLabel("Open movie in separate window")
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
        .accessibilityLabel("Open seat map")
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
        .accessibilityLabel("Open chat appearance settings")
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
        .accessibilityLabel("Exit theater experience")
    }

    // MARK: - Full Exit Handler
    // NavBarView.swift
    private func handleExit() async {
        print("📤 Full exit requested")

        // 1️⃣ Flush watch‑time stats (if you need them)
        let stats = await videoSyncService.getWatchStats()

        // 2️⃣ Clean up sync — this:
        //    • pauses / stops the player
        //    • removes listeners & timers
        //    • deletes your presence doc
        //    • triggers host‑election *after* the delete (only if you were host)
        await videoSyncService.cleanup(level: .full)

        // 3️⃣ Tear down the immersive space
        await spaceManager.initiateCleanup()

        // 4️⃣ Dismiss UI windows
        dismissWindow(id: "chatWindow")
        dismissWindow(id: "emojiWindow")
        dismissWindow(id: "movieWindow")
        dismissWindow(id: "seatMap")
        dismissWindow(id: "chatSettings")
        dismissWindow(id: "navBar")

        // 5️⃣ Show the “stats / goodbye” window
        try? await Task.sleep(for: .milliseconds(100))
        if !windowManager.isWindowOpen(.exitingWindow) {
            openWindow(id: WindowType.exitingWindow.rawValue, value: stats)
            windowManager.windowOpened(.exitingWindow)
        }

        print("✅ Exit sequence complete")
    }

}
