//
//  InteractiveStoryView.swift
//  Movie Theater Experience
//
//  Updated to fix compiler errors and connection state handling.
//

import SwiftUI
import AVKit
import Accelerate

struct InteractiveStoryView: View {

    @StateObject private var viewModel: InteractiveStoryViewModel
    
    init(story: Story) {
        _viewModel = StateObject(wrappedValue: InteractiveStoryViewModel(story: story))
    }

    // MARK: - Main body
    var body: some View {
        ZStack(alignment: .center) {

            /* ── 1  VIDEO SURFACE ── */
            ZStack {
                BarePlayerContainer(player: viewModel.videoPlayer)
                    .blur(radius: viewModel.isVideoBuffering ? 10 : 0)
                
                if viewModel.isVideoBuffering {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task {
                await viewModel.prepare()
            }

            /* ── 2  VIDEO BUTTONS (only while playing) ── */
            VStack {
                HStack {
                    Spacer()
                    if viewModel.sessionState == .playing {
                        topRightVideoControls
                            .transition(.opacity)
                    }
                }
                Spacer()
            }

            /* ── 3  BOTTOM OVERLAYS ── */
            VStack {
                Spacer()
                switch viewModel.sessionState {
                case .playing:
                    bottomAudioOverlay
                case .connecting:
                    connectingOverlay
                case .interacting:
                    interactingOverlay
                case .disconnected:
                    disconnectedOverlay
                // --- END ---
                }
            }
            .animation(.easeInOut, value: viewModel.sessionState)
            .padding(.bottom, 20)
        }
        .navigationTitle(viewModel.story.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { viewModel.cleanup() }
        .alert("Storyteller Interaction", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Top-right video controls
    private var topRightVideoControls: some View {
        HStack(spacing: 10) {
            // **FIX**: Using explicit closure syntax for all buttons to avoid compiler errors.
            Button(action: { viewModel.previousVideo() }) { Image(systemName: "backward.fill") }
            Button(action: { viewModel.replayCurrentVideo() }) { Image(systemName: "gobackward") }
            Button(action: { viewModel.playPauseVideoToggle() }) { Image(systemName: viewModel.isVideoPlaying ? "pause.fill" : "play.fill") }
            Button(action: { viewModel.nextVideo() }) { Image(systemName: "forward.fill") }
            Button(action: { viewModel.toggleVideoMute() }) { Image(systemName: viewModel.isVideoMuted ? "speaker.slash.fill" : "speaker.wave.3.fill") }
        }
        .font(.footnote)
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(.thinMaterial, in: Capsule())
        .padding(.trailing, 10).padding(.top, 10)
    }
    
    private var connectionStatusIndicator: some View {
        Group {
            switch viewModel.liveStorytellerService.status {
            case .connecting:
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Connecting...").font(.caption)
                }
            case .connected:
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Connected").font(.caption)
                }
            case .error:
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text("Connection Error").font(.caption)
                }
            case .permissionDenied:
                HStack {
                    Image(systemName: "mic.slash.fill").foregroundColor(.orange)
                    Text("Mic Permission Denied").font(.caption)
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    private var disconnectedOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.red)
            
            Text("Connection Lost")
                .font(.headline)
            
            Text(viewModel.errorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 15) {
                Button(action: { viewModel.returnToStory() }) {
                    Text("Back to Story")
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                
                Button(action: { viewModel.retryConnection() }) { // <-- Correct syntax
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Bottom AUDIO overlay
    private var bottomAudioOverlay: some View {
        VStack(spacing: 15) {
            AudioWaveformView(audioLevels: viewModel.audioLevels)
                .frame(height: 50)

            HStack(spacing: 12) {
                Button(action: { viewModel.playPauseAudioToggle() }) {
                    Label(viewModel.isAudioPlaying ? "" : "", systemImage: viewModel.isAudioPlaying ? "pause.circle.fill" : "play.circle.fill")
                }
                .font(.title2)
                .tint(.purple)
                
                VStack(spacing: 6) {
                    if viewModel.isNarrationBuffering {
                        ProgressView().tint(.purple)
                    } else {
                        ThinTrackSlider(
                            value: $viewModel.audioCurrentTime,
                            range: 0...max(1, viewModel.audioDuration),
                            onEditingChanged: viewModel.audioScrubbingChanged
                        )
                    }
                    HStack {
                        Text(formatTime(viewModel.audioCurrentTime))
                        Spacer()
                        Text(formatTime(viewModel.audioDuration))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Button(action: { viewModel.decreaseVolume() }) { Image(systemName: viewModel.volume <= 0 ? "speaker.slash" : "speaker.minus.fill") }
                    .disabled(viewModel.volume <= 0.0)
                
                Button(action: { viewModel.increaseVolume() }) { Image(systemName: viewModel.volume >= 1.0 ? "speaker.wave.3.fill" : "speaker.plus.fill") }
                    .disabled(viewModel.volume >= 1.0)
                
                Button(action: { viewModel.skipToInteraction() }) { Text("Skip") }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
            .font(.title3)
            .tint(.purple)
            .disabled(viewModel.isNarrationBuffering)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Connecting overlay
    private var connectingOverlay: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .purple))
            
            Text("Connecting to Storyteller...")
                .font(.headline)
            
            Text("This may take a moment")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: { viewModel.returnToStory() }) { Text("Cancel") }
                .buttonStyle(.bordered)
                .tint(.secondary)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Interaction overlay
    private var interactingOverlay: some View {
        VStack(spacing: 10) {
            connectionStatusIndicator
                .transition(.opacity)
            
            AudioWaveformView(audioLevels: viewModel.audioLevels)
                .frame(height: 50)

            HStack(spacing: 12) {
                if viewModel.liveStorytellerService.isMicrophoneAvailable {
                    Button(action: { viewModel.toggleMic() }) { Image(systemName: viewModel.isMicMuted ? "mic.slash.fill" : "mic.fill") }
                        .font(.title3)
                } else {
                    Image(systemName: "mic.slash.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                        .help("No microphone available")
                }

                TextField("Type a message…", text: $viewModel.textDraft, onCommit: viewModel.sendTextMessage)
                    .textFieldStyle(.roundedBorder)

                Button(action: { viewModel.sendTextMessage() }) { Image(systemName: "paperplane.fill") }

                Button(action: { viewModel.returnToStory() }) { Text("Back") }
                    .buttonStyle(.bordered)
            }
            
            if !viewModel.liveStorytellerService.isMicrophoneAvailable {
                Text("Voice input unavailable - use text instead")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
