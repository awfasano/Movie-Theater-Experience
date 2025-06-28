//  SpatialAudioLoader.swift  (slim spatial-only version)
//  Plays every track through RealityKit speakers and exposes
//  simple playback state.  Updated for Swift 6 strict concurrency
//  by hopping back to MainActor inside the Timer closure.

import Foundation
import FirebaseStorage
import RealityKit
import AVFoundation
import Combine

@MainActor
final class SpatialAudioLoader: ObservableObject {

    // ────────── Public @Published state the UI observes
    @Published private(set) var currentTrackIndex: Int = 0
    @Published private(set) var isPlaying          = false
    @Published               var trackDuration     = 0.0     // seconds
    @Published               var currentTime       = 0.0     // seconds
    
    private var resourceCache: [String: AudioFileResource] = [:]


    // ────────── Injected once at startup
    private weak var appModel: AppModel?               // to fetch current space name
    func attach(appModel: AppModel) { self.appModel = appModel }
    func getVolume() -> Float { masterVolume }


    // ────────── Private stored state
    private let storage = Storage.storage()
    private var songs: [Song]          = []            // fed by SongService
     var masterVolume: Float    = 0.4

    private var speakerEntities: [Entity] = []         // cached after first load
    private var controllers: [AudioPlaybackController] = []
    private var audioResource: AudioFileResource?      // keep for seek

    // progress clock
    private var clock: Timer?
    private var playStart: Date?                       // when the current play() began
    private var accumulated: TimeInterval = 0          // survives pauses to keep global time

    // MARK: ––––– Public API –––––––––––––––––––––––––––––––––––––––––––––––

    func setSongs(_ newSongs: [Song]) { songs = newSongs }

    /// Loads speakers in the space (only once) then plays first track.
    func loadAudioForSpace(rootEntity: Entity,
                           completion: @escaping (Bool)->Void = { _ in }) async {
        speakerEntities = findSpeakers(in: rootEntity)
        guard !speakerEntities.isEmpty, !songs.isEmpty else { completion(false); return }

        currentTrackIndex = 0
        await playCurrentTrack(completion: completion)
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func nextTrack() {
        guard !songs.isEmpty else { return }
        currentTrackIndex = (currentTrackIndex + 1) % songs.count
        Task { await playCurrentTrack() }
    }

    func previousTrack() {
        guard !songs.isEmpty else { return }
        currentTrackIndex = (currentTrackIndex - 1 + songs.count) % songs.count
        Task { await playCurrentTrack() }
    }

    func setVolume(_ v: Float) {
        masterVolume = max(0, min(1, v))
        updateSpeakerGains()
    }

    /// Scrub to a specific second using RealityKit's `seek(to:)`.
    func seek(to seconds: Double) {
        guard let res = audioResource else { return }
        stopControllers()
        accumulated = seconds
        playStart   = Date()
        startControllers(with: res, at: seconds)
        startClock()
    }

    // MARK: ––––– Core playback –––––––––––––––––––––––––––––––––––––––––––

    /// Plays `songs[currentTrackIndex]`.
    /// If the resource was loaded before we reuse it from `resourceCache`.
    private func playCurrentTrack(
        completion: @escaping (Bool) -> Void = { _ in }
    ) async {

        stopControllers()
        stopClock()

        let song      = songs[currentTrackIndex]
        let spaceName = appModel?.selectedSpace?.spaceName ?? "Music"

        // ─── Build Firebase reference ───────────────────────────────────────
        let ref: StorageReference
        if song.storageName.hasPrefix("https://") {
            ref = Storage.storage().reference(forURL: song.storageName)
        } else {
            ref = storage.reference()
                         .child("Music/\(spaceName)/\(song.storageName)")
        }

        // original file name (for extension & cache key)
        let originalName = URL(string: song.storageName)?.lastPathComponent
                        ?? (song.storageName as NSString).lastPathComponent

        // ─── 1) check cache ─────────────────────────────────────────────────
        if let cached = resourceCache[song.storageName] {
            audioResource = cached
            accumulated   = 0
            playStart     = Date()
            startControllers(with: cached, at: 0)
            startClock()
            isPlaying = true
            completion(true)
            return
        }

        // ─── 2) not cached → download & register ────────────────────────────
        do {
            let url = try await downloadTempFile(from: ref,
                                                 preferredName: originalName)

            // ask AVFoundation for track length
            let asset    = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            trackDuration = CMTimeGetSeconds(duration)

            // unique alias (sanitised base + UUID)
            let baseAlias = sanitiseAlias(originalName)       // Clouds.wav → Clouds.wav
            let alias     = "\(baseAlias)_\(UUID().uuidString)"

            // RealityKit resource
            let res = try await AudioFileResource(
                contentsOf:   url,
                withName:     alias,
                configuration: .init(shouldLoop: false)
            )

            // cache & play
            resourceCache[song.storageName] = res
            audioResource = res
            accumulated   = 0
            playStart     = Date()
            startControllers(with: res, at: 0)
            startClock()
            isPlaying = true
            completion(true)

        } catch {
            print("❌ SpatialAudioLoader error:", error)
            completion(false)
        }
    }



    private func startControllers(with res: AudioFileResource, at offset: Double) {
        controllers = speakerEntities.map { speaker in
            var comp = speaker.components[SpatialAudioComponent.self] ?? .init()
            comp.gain = Audio.Decibel(linearToDB(masterVolume))
            speaker.components[SpatialAudioComponent.self] = comp

            let ctrl = speaker.prepareAudio(res)
            ctrl.play()
            if offset > 0 { ctrl.seek(to: .seconds(offset)) }
            return ctrl
        }
    }

    private func pause() {
        isPlaying = false
        controllers.forEach { $0.pause() }
        accumulated += Date().timeIntervalSince(playStart ?? Date())
        stopClock()
    }

    private func resume() {
        guard !controllers.isEmpty else { return }
        isPlaying = true
        controllers.forEach { $0.play() }
        playStart = Date()
        startClock()
    }

    private func stopControllers() {
        controllers.forEach { $0.stop() }
        controllers.removeAll()
    }

    // MARK: ––––– Progress clock ––––––––––––––––––––––––––––––––––––––––––

    private func startClock() {
        stopClock()
        clock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying else { return }

                let elapsed = self.accumulated + Date().timeIntervalSince(self.playStart ?? Date())
                self.currentTime = elapsed

                // NEW — when we reach / pass the duration
                if elapsed >= self.trackDuration {
                    self.nextTrack()                 // modulo makes 0 after the last song
                }
            }
        }
        RunLoop.main.add(clock!, forMode: .common)
    }

    private func stopClock() { clock?.invalidate(); clock = nil }

    // MARK: ––––– Helpers ––––––––––––––––––––––––––––––––––––––––––––––––

    private func updateSpeakerGains() {
        let db = linearToDB(masterVolume)
        for speaker in speakerEntities {
            var comp = speaker.components[SpatialAudioComponent.self] ?? .init()
            comp.gain = Audio.Decibel(db)
            speaker.components[SpatialAudioComponent.self] = comp
        }
    }

    /// Downloads the Firebase object into the temp directory,
    /// keeping the original extension (.wav / .m4a / etc.).
    private func downloadTempFile(from ref: StorageReference,
                                  preferredName: String) async throws -> URL {

        // preserve extension; default to "wav" if none
        let ext = (preferredName as NSString).pathExtension
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "wav" : ext)

        let data = try await ref.data(maxSize: 50 * 1024 * 1024)   // 50 MB cap
        try data.write(to: tmp, options: .atomic)
        return tmp
    }


    
    // MARK: - Stop everything
    @MainActor
    func stopAllAudio() {
        stopControllers()
        stopClock()
        isPlaying = false
        resourceCache.removeAll()   // ← optional, if you want a full flush
    }
    
    private func sanitiseAlias(_ fileName: String) -> String {
        let ext  = (fileName as NSString).pathExtension
        let base = ((fileName as NSString).deletingPathExtension)
            .replacingOccurrences(of: "[^A-Za-z0-9_\\-]", with: "_",
                                  options: .regularExpression)
        return "\(base).\(ext)"
    }


    func findSpeakers(in root: Entity) -> [Entity] {
        var out: [Entity] = []
        if root.name.hasPrefix("speaker_") { out.append(root) }
        for child in root.children { out += findSpeakers(in: child) }
        return out
    }

    func linearToDB(_ v: Float) -> Float { v <= 0 ? -80 : 20 * log10(v) }
}
