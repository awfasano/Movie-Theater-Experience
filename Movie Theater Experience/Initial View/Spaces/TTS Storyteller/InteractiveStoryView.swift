//
//  InteractiveStoryView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 6/21/25.
//  Re-organised on 6/24/25
//    • video buttons float top-right
//    • taller waveform
//    • audio slider + narration button share the bottom stack
//  Updated 6/25/25
//    • Added mute button and vertical volume slider
//

import SwiftUI
import AVKit
import Accelerate

/// **Assumes** you’ve already added `BarePlayerView` + `BarePlayerContainer` from PlayerView.swift.
struct InteractiveStoryView: View {

    // MARK: – View-model
    @StateObject private var viewModel: InteractiveStoryViewModel
    

    init(story: Story) {
        _viewModel = StateObject(wrappedValue: InteractiveStoryViewModel(story: story))
    }

    // MARK: – Main body ------------------------------------------------------
    var body: some View {
        ZStack(alignment: .topTrailing) {

            /* ── 1  VIDEO SURFACE  ────────────────────────────────────────── */
            // Using a bare player view prevents the default system controls from appearing.
            BarePlayerContainer(player: viewModel.videoPlayer)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            /* ── 2  VIDEO BUTTONS (only while playing)  ─────────────────── */
            if viewModel.sessionState == .playing {
                topRightVideoControls
                    .transition(.opacity)
            }

            /* ── 3  BOTTOM OVERLAYS  ─────────────────────────────────────── */
            VStack {
                Spacer()                                        // push down
                switch viewModel.sessionState {
                case .playing:     bottomAudioOverlay
                case .interacting: interactingOverlay
                }
            }
            .animation(.easeInOut, value: viewModel.sessionState) // Animate overlay transition
            .padding(.bottom, 20)
        }
        .navigationTitle(viewModel.story.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { viewModel.cleanup() }
    }

    // MARK: – Top-right video controls --------------------------------------
    private var topRightVideoControls: some View {
        HStack(spacing: 10) {
            Button(action: viewModel.previousVideo) { Image(systemName: "backward.fill") }
            Button(action: viewModel.replayCurrentVideo) { Image(systemName: "gobackward") }
            Button(action: viewModel.playPauseVideoToggle) { Image(systemName: viewModel.isVideoPlaying ? "pause.fill" : "play.fill") }
            Button(action: viewModel.nextVideo) { Image(systemName: "forward.fill") }
            
            // Mute button for the video
            // 💡 UNCOMMENTED the action and image logic
            Button(action: {
                viewModel.toggleVideoMute()
            }) {
                Image(systemName: viewModel.isVideoMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
            }
        }
        .font(.footnote)
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(.thinMaterial, in: Capsule())
        .padding(.trailing, 10).padding(.top, 10)
    }

    // MARK: – Bottom AUDIO overlay -----------------------------------------
    private var bottomAudioOverlay: some View {
        VStack(spacing: 15) {

            /* ➊ Waveform  */
            AudioWaveformView(audioLevels: viewModel.audioLevels)
                .frame(height: 50)

            /* ➋ Scrubber + main controls row */
            HStack(spacing: 12) { // Adjusted spacing for new buttons
                
                /* Play/Pause Button */
                Button(action: viewModel.playPauseAudioToggle) {
                    Label(viewModel.isAudioPlaying ? "" : "",
                          systemImage: viewModel.isAudioPlaying ? "pause.circle.fill" : "play.circle.fill")
                }
                .font(.title2) // Slightly larger
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
                
                // 💡 --- NEW INTEGRATED VOLUME CONTROLS --- 💡
                
                // Volume Down Button
                Button(action: viewModel.decreaseVolume) {
                    // Icon changes to an "X" when volume is zero
                    Image(systemName: viewModel.volume <= 0 ? "speaker.slash" : "speaker.minus.fill")
                }
                .disabled(viewModel.volume <= 0.0)
                
                // Volume Up Button
                Button(action: viewModel.increaseVolume) {
                    // Icon changes to "max" when volume is full
                    Image(systemName: viewModel.volume >= 1.0 ? "speaker.wave.3.fill" : "speaker.plus.fill")
                }
                .disabled(viewModel.volume >= 1.0)
                
                // 💡 --- END OF NEW CONTROLS --- 💡
                
                /* Skip button */
                Button("Skip", action: viewModel.skipToInteraction)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
            .font(.title3) // Set a base size for the new buttons
            .tint(.purple) // Set a base color for the new buttons
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
        // The .overlay is no longer needed here
    }
    


    // MARK: – Interaction overlay -------------------------------------------
    private var interactingOverlay: some View {
        VStack(spacing: 10) {

            /* ➊ Shared waveform */
            AudioWaveformView(audioLevels: viewModel.audioLevels)
                .frame(height: 50)

            /* ➋ Mic-text-buttons row */
            HStack(spacing: 12) {
                // mic toggle
                Button(action: viewModel.toggleMic) {
                    Image(systemName: viewModel.isMicMuted ? "mic.slash.fill" : "mic.fill")
                }
                .font(.title3)

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

        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
    }


    // MARK: – Helper ---------------------------------------------------------
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
