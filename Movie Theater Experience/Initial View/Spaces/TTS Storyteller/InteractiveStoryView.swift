//
//  InteractiveStoryView.swift
//  Movie Theater Experience
//
//  Updated to handle connecting state
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
        ZStack(alignment: .topTrailing) {

            /* ── 1  VIDEO SURFACE ── */
            BarePlayerContainer(player: viewModel.videoPlayer)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .task {
                    await viewModel.prepare()
                }

            /* ── 2  VIDEO BUTTONS (only while playing) ── */
            if viewModel.sessionState == .playing {
                topRightVideoControls
                    .transition(.opacity)
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
                }
            }
            .animation(.easeInOut, value: viewModel.sessionState)
            .padding(.bottom, 20)
        }
        .navigationTitle(viewModel.story.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { viewModel.cleanup() }
        .alert("Audio Connection Error", isPresented: $viewModel.showingError) {
            Button("Retry") {
                viewModel.retryConnection()
            }
            Button("Back to Story") {
                viewModel.returnToStory()
            }
            Button("Cancel", role: .cancel) {
                viewModel.showingError = false
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Top-right video controls
    private var topRightVideoControls: some View {
        HStack(spacing: 10) {
            Button(action: { viewModel.previousVideo() }) {
                Image(systemName: "backward.fill")
            }
            Button(action: { viewModel.replayCurrentVideo() }) {
                Image(systemName: "gobackward")
            }
            Button(action: { viewModel.playPauseVideoToggle() }) {
                Image(systemName: viewModel.isVideoPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: { viewModel.nextVideo() }) {
                Image(systemName: "forward.fill")
            }
            Button(action: { viewModel.toggleVideoMute() }) {
                Image(systemName: viewModel.isVideoMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
            }
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
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting...")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                
            case .connected:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connected")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                
            case .error:
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Connection Error")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                
            case .permissionDenied:
                HStack {
                    Image(systemName: "mic.slash.fill")
                        .foregroundColor(.orange)
                    Text("Mic Permission Required")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Bottom AUDIO overlay
    private var bottomAudioOverlay: some View {
        VStack(spacing: 15) {

            /* ➊ Waveform */
            AudioWaveformView(audioLevels: viewModel.audioLevels)
                .frame(height: 50)

            /* ➋ Scrubber + main controls row */
            HStack(spacing: 12) {
                
                /* Play/Pause Button */
                Button(action: viewModel.playPauseAudioToggle) {
                    Label(viewModel.isAudioPlaying ? "" : "",
                          systemImage: viewModel.isAudioPlaying ? "pause.circle.fill" : "play.circle.fill")
                }
                .font(.title2)
                .tint(.purple)
                
                /* Scrubber */
                VStack(spacing: 6) {
                    ThinTrackSlider(
                        value: $viewModel.audioCurrentTime,
                        range: 0...max(1, viewModel.audioDuration),
                        onEditingChanged: viewModel.audioScrubbingChanged
                    )
                    HStack {
                        Text(formatTime(viewModel.audioCurrentTime))
                        Spacer()
                        Text(formatTime(viewModel.audioDuration))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                // Volume Down Button
                Button(action: viewModel.decreaseVolume) {
                    Image(systemName: viewModel.volume <= 0 ? "speaker.slash" : "speaker.minus.fill")
                }
                .disabled(viewModel.volume <= 0.0)
                
                // Volume Up Button
                Button(action: viewModel.increaseVolume) {
                    Image(systemName: viewModel.volume >= 1.0 ? "speaker.wave.3.fill" : "speaker.plus.fill")
                }
                .disabled(viewModel.volume >= 1.0)
                
                /* Skip button */
                Button("Skip", action: viewModel.skipToInteraction)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
            .font(.title3)
            .tint(.purple)
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
            
            Button("Cancel") {
                viewModel.returnToStory()
            }
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
            
            /* ➊ Shared waveform */
            AudioWaveformView(audioLevels: viewModel.audioLevels)
                .frame(height: 50)

            /* ➋ Mic-text-buttons row */
            HStack(spacing: 12) {
                // mic toggle - only show if microphone is available
                if viewModel.liveStorytellerService.isMicrophoneAvailable {
                    Button(action: viewModel.toggleMic) {
                        Image(systemName: viewModel.isMicMuted ? "mic.slash.fill" : "mic.fill")
                    }
                    .font(.title3)
                } else {
                    Image(systemName: "mic.slash.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                        .help("No microphone available")
                }

                // text field
                TextField("Type a message…", text: $viewModel.textDraft, onCommit: {
                    viewModel.sendTextMessage()
                })
                .textFieldStyle(.roundedBorder)

                // send button
                Button(action: viewModel.sendTextMessage) {
                    Image(systemName: "paperplane.fill")
                }

                // back-to-story
                Button("Back") { viewModel.returnToStory() }
                    .buttonStyle(.bordered)
            }
            
            // Show a message if no microphone is available
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

    // MARK: - Helper
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
