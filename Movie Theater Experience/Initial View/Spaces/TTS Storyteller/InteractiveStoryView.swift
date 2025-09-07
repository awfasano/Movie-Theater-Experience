//
//  InteractiveStoryView.swift
//  Movie Theater Experience
//
//  Updated to include transcript display during interaction
//

import SwiftUI
import AVKit
import Accelerate

struct InteractiveStoryView: View {

    @StateObject private var viewModel: InteractiveStoryViewModel
    @State private var showTranscripts = false
    @FocusState private var isTextFieldFocused: Bool  // Add this

    
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
        .sheet(isPresented: $showTranscripts) {
            transcriptSheet
        }
    }

    // MARK: - Top-right video controls
    private var topRightVideoControls: some View {
        HStack(spacing: 10) {
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
            Image(systemName: getErrorIcon())
                .font(.largeTitle)
                .foregroundStyle(getErrorColor())
            
            Text(getErrorTitle())
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
                
                Button(action: {
                    if isServiceUnavailable() {
                        //viewModel.liveStorytellerService.retryConnection()
                    } else {
                        viewModel.retryConnection()
                    }
                }) {
                    Label(getRetryButtonText(), systemImage: "arrow.clockwise")
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

    private func isServiceUnavailable() -> Bool {
        return viewModel.errorMessage.contains("service is temporarily unavailable") ||
               viewModel.errorMessage.contains("internal error") ||
               viewModel.errorMessage.contains("AI storyteller service is temporarily unavailable") ||
               viewModel.errorMessage.contains("high demand")
    }

    private func getErrorIcon() -> String {
        if isServiceUnavailable() {
            return "exclamationmark.triangle"
        }
        return "wifi.exclamationmark"
    }

    private func getErrorColor() -> Color {
        if isServiceUnavailable() {
            return .orange
        }
        return .red
    }

    private func getErrorTitle() -> String {
        if isServiceUnavailable() {
            return "Service Temporarily Unavailable"
        }
        return "Connection Lost"
    }

    private func getRetryButtonText() -> String {
        if isServiceUnavailable() {
            return "Try Again"
        }
        return "Retry"
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

    // MARK: - Interaction overlay with transcripts
    private var interactingOverlay: some View {
        VStack(spacing: 10) {
            // Status and transcript toggle
            HStack {
                connectionStatusIndicator
                
                // Show sending/waiting indicators
                if viewModel.liveStorytellerService.isSendingAudio {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.red)
                            .symbolEffect(.pulse)
                        Text("Speaking...")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                } else if viewModel.liveStorytellerService.isSendingText {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Sending...")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                } else if viewModel.liveStorytellerService.isWaitingForResponse {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                            .symbolEffect(.pulse)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
                
                // Transcript badge
                if !viewModel.liveStorytellerService.transcripts.isEmpty {
                    Button(action: { showTranscripts.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                            Text("\(viewModel.liveStorytellerService.transcripts.count)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                }
            }
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.3), value: viewModel.liveStorytellerService.isSendingAudio)
            .animation(.easeInOut(duration: 0.3), value: viewModel.liveStorytellerService.isSendingText)
            .animation(.easeInOut(duration: 0.3), value: viewModel.liveStorytellerService.isWaitingForResponse)
            
            AudioWaveformView(audioLevels: viewModel.audioLevels)
                .frame(height: 50)

            HStack(spacing: 12) {
                // Mic button with visual feedback when active
                if viewModel.liveStorytellerService.isMicrophoneAvailable {
                    Button(action: { viewModel.toggleMic() }) {
                        ZStack {
                            if !viewModel.isMicMuted && viewModel.liveStorytellerService.isSendingAudio {
                                Circle()
                                    .fill(Color.red.opacity(0.2))
                                    .frame(width: 44, height: 44)
                                    .scaleEffect(1.2)
                                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: viewModel.liveStorytellerService.isSendingAudio)
                            }
                            
                            Image(systemName: viewModel.isMicMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.title3)
                                .foregroundColor(viewModel.isMicMuted ? .gray : (viewModel.liveStorytellerService.isSendingAudio ? .red : .purple))
                        }
                    }
                } else {
                    Image(systemName: "mic.slash.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                        .help("No microphone available")
                }

                TextField("Type a message…", text: $viewModel.textDraft, onCommit: viewModel.sendTextMessage)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.liveStorytellerService.isSendingText)
                    .focused($isTextFieldFocused)  // Add focus binding
                    .onChange(of: isTextFieldFocused) { newValue in
                        viewModel.handleTextFieldFocusChange(newValue)
                    }

                Button(action: { viewModel.sendTextMessage() }) {
                    if viewModel.liveStorytellerService.isSendingText {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(viewModel.textDraft.isEmpty || viewModel.liveStorytellerService.isSendingText)

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
    
    // MARK: - Transcript Sheet
    private var transcriptSheet: some View {
        NavigationView {
            TranscriptView(transcripts: viewModel.liveStorytellerService.transcripts)
                .navigationTitle("Conversation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showTranscripts = false
                        }
                    }
                }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
