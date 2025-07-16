
import Foundation
import RealityKit
import Combine

@MainActor
final class AudioService: ObservableObject {
    /// The single, shared instance of the service.
    static let shared = AudioService()

    // MARK: - Published Properties for the UI
    @Published private(set) var songs: [Song] = []
    @Published private(set) var currentTrackIndex: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoadingTrack = false
    @Published var trackDuration = 0.0
    @Published var currentTime = 0.0

    // MARK: - Internal Services
    private let songService = SongService()
    let audioLoader = SpatialAudioLoader()

    // MARK: - State Tracking
    private var preparedSpaceName: String?
    private var hasBeenPrepared = false

    /// Private initializer to ensure singleton usage.
    private init() {
        // Connect the private audioLoader's state to our public properties.
        audioLoader.$isPlaying.assign(to: &$isPlaying)
        audioLoader.$isLoadingTrack.assign(to: &$isLoadingTrack)
        audioLoader.$trackDuration.assign(to: &$trackDuration)
        audioLoader.$currentTime.assign(to: &$currentTime)
        audioLoader.$currentTrackIndex.assign(to: &$currentTrackIndex)
    }

    /// The main entry point. Fetches songs and prepares the player, but only if it hasn't been done for the current space.
    func loadSongsAndPreparePlayer(for spaceName: String, rootEntity: Entity) async {
        // If we've already prepared for this space, do nothing.
        guard !hasBeenPrepared || spaceName != self.preparedSpaceName else {
            print("✅ AudioService already prepared for '\(spaceName)'.")
            return
        }
        
        print("⏳ AudioService preparing for '\(spaceName)'...")
        self.preparedSpaceName = spaceName
        self.isLoadingTrack = true

        // Fetch the song metadata.
        let fetchedSongs = await songService.fetchSongs(for: spaceName)
        self.songs = fetchedSongs
        
        guard !fetchedSongs.isEmpty else {
            print("❌ No songs found. Halting audio preparation.")
            self.isLoadingTrack = false
            return
        }

        // Load the songs into the player and find the speakers.
        audioLoader.setSongs(fetchedSongs)
        await audioLoader.loadAudioForSpace(rootEntity: rootEntity)

        self.hasBeenPrepared = true
    }

    /// Resets the audio state completely. Called when the immersive space closes.
    func cleanup() {
        audioLoader.stopAllAudio()
        self.songs = []
        self.hasBeenPrepared = false
        self.preparedSpaceName = nil
        print("🎶 AudioService state cleaned up.")
    }

    // MARK: - Public Playback Controls
    func togglePlayPause() { audioLoader.togglePlayPause() }
    func nextTrack() { audioLoader.nextTrack() }
    func previousTrack() { audioLoader.previousTrack() }
    func seek(to seconds: Double) { audioLoader.seek(to: seconds) }
    func setVolume(_ volume: Float) { audioLoader.setVolume(volume) }
}
