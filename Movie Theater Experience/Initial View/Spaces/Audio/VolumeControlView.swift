import SwiftUI
import RealityKit
import Combine

struct VolumeControlView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var wrapper: SpacesEntityWrapper
    @ObservedObject var audioLoader: SpatialAudioLoader

    @StateObject private var songService = SongService()
    @State private var volume: Float
    @State private var isExpanded = true
    @State private var isPlaying: Bool

    @State private var isDragging = false
    @State private var sliderPosition = 0.0
    @State private var audioDuration = 0.0
    @State private var pulse = false

    @State private var songsC: AnyCancellable?
    @State private var playC:  AnyCancellable?
    @State private var timeC:  AnyCancellable?
    @State private var durC:   AnyCancellable?

    private let spaceEntity: Entity
    private let spaceMeta: SpaceData

    init(audioLoader: SpatialAudioLoader, spaceEntity: Entity, spaceMeta: SpaceData) {
        self.audioLoader = audioLoader
        self.spaceEntity = spaceEntity
        self.spaceMeta = spaceMeta
        _volume = State(initialValue: audioLoader.getVolume())
        _isPlaying = State(initialValue: audioLoader.isPlaying)
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedView.frame(width: 300)
            } else {
                collapsedView.frame(width: 360)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.75))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)
        .onAppear(perform: setUpBindings)
        .onChange(of: isExpanded) { _, expanded in
            if expanded && isPlaying {
                pulse = true
            }
        }
        .onDisappear(perform: tearDown)
    }

    // MARK: - Expanded
    private var expandedView: some View {
        VStack(spacing: 14) {
            header
            if let song = songService.songs[safe: audioLoader.currentTrackIndex] {
                songDisplay(song)
            }
            progressBar
            transport
            volumeSlider
                .padding(.bottom, 10)
        }
    }

    // MARK: - Collapsed
    private var collapsedView: some View {
        HStack(spacing: 14) {
            Button { withAnimation { isExpanded.toggle() } } label: {
                Image(systemName: "chevron.up").foregroundColor(.white)
            }

            if let song = songService.songs[safe: audioLoader.currentTrackIndex] {
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
                    audioLoader.togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.bold()).foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

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
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(pulse ? 0.8 : 0.3), lineWidth: 4)
                                .shadow(color: Color.purple.opacity(pulse ? 0.7 : 0), radius: pulse ? 8 : 0)
                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
                        )
                        .scaleEffect(pulse ? 1.05 : 1.0)
                        .animation(isPlaying ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default, value: pulse)
                        .onAppear { if isPlaying { pulse = true } }
                        .onChange(of: isPlaying) { _, playing in pulse = playing }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 180, height: 180)
                        .cornerRadius(12)
                }
            }

            VStack(spacing: 2) {
                Text(song.song).font(.headline.bold()).foregroundColor(.white)
                Text(song.artist).font(.subheadline).foregroundColor(.gray)
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            if audioDuration > 0 {
                ThinTrackSlider(
                    value: $sliderPosition,
                    range: 0...audioDuration,
                    onEditingChanged: { editing in
                        isDragging = editing
                        if !editing {
                            audioLoader.seek(to: sliderPosition)
                        }
                    }
                )
                .frame(height: 20)                // total control height
                .padding(.horizontal, 10)
                .shadow(color: Color.purple.opacity(0.8), radius: 3)

                HStack {
                    Text(formatTime(sliderPosition))
                    Spacer()
                    Text(formatTime(audioDuration))
                }
                .font(.caption2)
                .foregroundColor(.gray)
                .frame(width: 260)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
    }



    private var transport: some View {
        HStack(spacing: 40) {
            Button { audioLoader.previousTrack() } label: {
                Image(systemName: "backward.fill").font(.title2.bold()).foregroundColor(.white)
            }

            Button { audioLoader.togglePlayPause() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle.bold()).foregroundColor(.white)
            }

            Button { audioLoader.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.title2.bold()).foregroundColor(.white)
            }
        }
    }

    private var volumeSlider: some View {
        HStack {
            Image(systemName: "speaker.fill").foregroundColor(.white)
            Slider(value: $volume, in: 0...1, onEditingChanged: { editing in
                if !editing {
                    audioLoader.setVolume(volume)
                }
            })
            .accentColor(.purple)
            .frame(width: 240)
            Image(systemName: "speaker.wave.3.fill").foregroundColor(.white)
        }
    }

    // MARK: - Helpers
    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func setUpBindings() {
        songsC = songService.$songs
            .receive(on: RunLoop.main)
            .sink { songs in
                audioLoader.setSongs(songs)
                if !songs.isEmpty {
                    Task {
                        await audioLoader.loadAudioForSpace(rootEntity: spaceEntity)
                    }
                }
            }

        playC = audioLoader.$isPlaying
            .receive(on: RunLoop.main)
            .sink { val in self.isPlaying = val }

        timeC = audioLoader.$currentTime
            .receive(on: RunLoop.main)
            .sink { t in if !isDragging { self.sliderPosition = t } }

        durC = audioLoader.$trackDuration
            .receive(on: RunLoop.main)
            .sink { d in self.audioDuration = d }
    }

    private func tearDown() {
        [songsC, playC, timeC, durC].forEach { $0?.cancel() }
    }
}

// MARK: - Safe Array Access
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
