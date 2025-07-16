import SwiftUI
import RealityKit
import Combine

struct VolumeControlView: View {
    // MARK: - Properties
    
    /// The single, shared instance of the audio service. This is the source of truth for all audio state.
    @StateObject private var audioService = AudioService.shared
    
    /// State properties that are specific to the UI of this view only.
    @State private var isExpanded = true
    @State private var isDraggingSlider = false
    @State private var pulse = false
    @State private var sliderVolume: Float = 0.5

    // MARK: - Body
    
    var body: some View {
        Group {
            if isExpanded {
                expandedView.frame(width: 300)
            } else {
                collapsedView.frame(width: 360)
            }
        }
        .padding(12)
        .background(.black.opacity(0.75))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)
        .onChange(of: isExpanded) { _, expanded in
            if expanded && audioService.isPlaying {
                pulse = true
            }
        }
        .onAppear {
            self.sliderVolume = audioService.audioLoader.getVolume()
        }
    }

    // MARK: - Expanded View
    
    private var expandedView: some View {
        VStack(spacing: 14) {
            header
            if let song = audioService.songs[safe: audioService.currentTrackIndex] {
                songDisplay(song)
            } else {
                placeholderSongDisplay()
            }
            progressBar
            transport
            volumeSlider
                .padding(.bottom, 10)
        }
    }

    // MARK: - Collapsed View
    
    private var collapsedView: some View {
        HStack(spacing: 14) {
            Button { withAnimation { isExpanded.toggle() } } label: {
                Image(systemName: "chevron.up").foregroundColor(.white)
            }

            if let song = audioService.songs[safe: audioService.currentTrackIndex] {
                AsyncImage(url: URL(string: song.artworkURL)) { phase in
                    if let image = try? phase.image?.resizable() {
                        image
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 42, height: 42)
                            .cornerRadius(6)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 42, height: 42)
                            .cornerRadius(6)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.song).font(.caption.bold()).foregroundColor(.white).lineLimit(1)
                    Text(song.artist).font(.caption2).foregroundColor(.gray).lineLimit(1)
                }

                Spacer()

                Button {
                    audioService.togglePlayPause()
                } label: {
                    Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.bold()).foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - View Components
    
    private var header: some View {
        HStack {
            Text("Now Playing").font(.title3.bold()).foregroundColor(.white)
            Spacer()
            Button { withAnimation { isExpanded.toggle() } } label: {
                Image(systemName: "chevron.down").foregroundColor(.white)
            }
        }
    }

    private func songDisplay(_ song: Song) -> some View {
        VStack(spacing: 8) {
            AsyncImage(url: URL(string: song.artworkURL)) { phase in
                if let image = try? phase.image?.resizable() {
                    image
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 180, height: 180)
                        .cornerRadius(12)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 180, height: 180)
                        .cornerRadius(12)
                }
            }
            .overlay {
                if audioService.isLoadingTrack {
                    ZStack {
                        Color.black.opacity(0.5).cornerRadius(12)
                        ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(1.5)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.purple.opacity(pulse ? 0.8 : 0.3), lineWidth: 4)
                    .shadow(color: Color.purple.opacity(pulse ? 0.7 : 0), radius: pulse ? 8 : 0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
            )
            .scaleEffect(pulse ? 1.05 : 1.0)
            .animation(audioService.isPlaying ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { if audioService.isPlaying { pulse = true } }
            .onChange(of: audioService.isPlaying) { _, playing in pulse = playing }

            VStack(spacing: 2) {
                Text(song.song).font(.headline.bold()).foregroundColor(.white)
                Text(song.artist).font(.subheadline).foregroundColor(.gray)
            }
        }
    }
    
    private func placeholderSongDisplay() -> some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 180, height: 180)
                .cornerRadius(12)
                .overlay {
                    if audioService.isLoadingTrack {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
                }
            
            VStack(spacing: 2) {
                Text("No Song Loaded").font(.headline.bold()).foregroundColor(.white)
                Text("Select a space").font(.subheadline).foregroundColor(.gray)
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            if audioService.trackDuration > 0 {
                // ✅ USE YOUR CUSTOM SLIDER
                ThinTrackSlider(
                    value: $audioService.currentTime,
                    range: 0...audioService.trackDuration,
                    onEditingChanged: { isEditing in
                        self.isDraggingSlider = isEditing
                        // Only seek when the user finishes dragging.
                        if !isEditing {
                            audioService.seek(to: audioService.currentTime)
                        }
                    }
                )
                .frame(height: 20)
                .padding(.horizontal, 10)

                HStack {
                    Text(formatTime(audioService.currentTime))
                    Spacer()
                    Text(formatTime(audioService.trackDuration))
                }
                .font(.caption2).foregroundColor(.gray).frame(width: 260)
            } else {
                ProgressView().progressViewStyle(.linear).tint(.white)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 40) {
            Button { audioService.previousTrack() } label: {
                Image(systemName: "backward.fill").font(.title2.bold()).foregroundColor(.white)
            }
            Button { audioService.togglePlayPause() } label: {
                Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle.bold()).foregroundColor(.white)
            }
            Button { audioService.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.title2.bold()).foregroundColor(.white)
            }
        }
    }

    private var volumeSlider: some View {
        HStack {
            Image(systemName: "speaker.fill").foregroundColor(.white)
            Slider(value: $sliderVolume, in: 0...1, onEditingChanged: { editing in
                if !editing {
                    audioService.setVolume(sliderVolume)
                }
            })
            .accentColor(.purple)
            .frame(width: 240)
            Image(systemName: "speaker.wave.3.fill").foregroundColor(.white)
        }
    }

    // MARK: - Helpers
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// Keep this helper for safe array access
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
