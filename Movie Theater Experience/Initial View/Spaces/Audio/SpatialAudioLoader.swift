//  SpatialAudioLoader.swift  (slim spatial-only version)
//  Plays every track through RealityKit speakers and exposes
//  simple playback state.  Updated for Swift 6 strict concurrency
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
    @Published               var trackDuration      = 0.0      // seconds
    @Published               var currentTime        = 0.0      // seconds
    @Published private(set) var isLoadingTrack: Bool = false // For UI loading indicator

    private var resourceCache: [String: AudioFileResource] = [:]


    // ────────── Injected once at startup
    private weak var appModel: AppModel?            // to fetch current space name
    func attach(appModel: AppModel) { self.appModel = appModel }
    func getVolume() -> Float { masterVolume }


    // ────────── Private stored state
    private let storage = Storage.storage()
    private var songs: [Song]        = []          // fed by SongService
     var masterVolume: Float   = 0.75

    private var speakerEntities: [Entity] = []        // cached after first load
    private var controllers: [AudioPlaybackController] = []
    private var audioResource: AudioFileResource?     // keep for seek

    // progress clock
    private var clock: Timer?
    private var playStart: Date?                      // when the current play() began
    private var accumulated: TimeInterval = 0         // survives pauses to keep global time
    
    // Used to prevent infinite loops if all songs are broken
    private var failedTrackIndices = Set<Int>()


    // MARK: ––––– Public API –––––––––––––––––––––––––––––––––––––––––––––––

    /// Loads speakers in the space (only once) then plays first track.
    // In SpatialAudioLoader.swift

    /// Loads speakers in the space (only once) then plays first track.
    func loadAudioForSpace(rootEntity: Entity,
                           completion: @escaping (Bool)->Void = { _ in }) async {
        
        // ✅ SOLUTION: Run the potentially slow scene search in a detached Task.
        // This moves the work to a background thread.
        let foundSpeakers = await Task.detached {
            self.findSpeakers(in: rootEntity)
        }.value
        
        // 'await' returns execution to the MainActor. It is now safe to
        // update our MainActor-isolated 'speakerEntities' property.
        self.speakerEntities = foundSpeakers
        print("🔊 Found \(speakerEntities.count) speaker entities.")
        
        // The rest of the function proceeds as before.
        guard !speakerEntities.isEmpty, !songs.isEmpty else {
            print("❌ Audio setup failed: Speaker count is \(speakerEntities.count), Song count is \(songs.count).")
            completion(false)
            return
        }

        currentTrackIndex = 0
        failedTrackIndices.removeAll()
        await playCurrentTrack(completion: completion)
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func nextTrack(userInitiated: Bool = true) {
        guard !songs.isEmpty else { return }
        
        // If this wasn't a user action, it's an auto-skip. Check for infinite loops.
        if !userInitiated {
            // If we've tried every song and failed, stop playback.
            if failedTrackIndices.count >= songs.count {
                print("❌ Halting playback: All songs in the playlist have failed to load.")
                self.isPlaying = false
                self.isLoadingTrack = false
                return
            }
        } else {
            // If the user manually skips, reset the failure tracking
            failedTrackIndices.removeAll()
        }

        currentTrackIndex = (currentTrackIndex + 1) % songs.count
        
        Task {
            await playAndPreload(direction: .forward)
        }
    }

    func previousTrack() {
        guard !songs.isEmpty else { return }
        
        // User action always resets failure tracking
        failedTrackIndices.removeAll()

        currentTrackIndex = (currentTrackIndex - 1 + songs.count) % songs.count
        
        Task {
            await playAndPreload(direction: .backward)
        }
    }

    func setVolume(_ v: Float) {
        masterVolume = max(0, min(1, v))
        updateSpeakerGains()
    }

    /// Scrub to a specific second using RealityKit's `seek(to:)`.
    func seek(to seconds: Double) {
        // Launch a new task to avoid blocking the caller (e.g., the UI thread).
        Task {
            // All RealityKit and state updates must be on the MainActor.
            await MainActor.run {
                guard let res = self.audioResource, self.isPlaying else { return }
                
                // Stop current playback and clocks
                self.stopControllers()
                self.stopClock()
                
                // Update time state
                self.accumulated = seconds
                self.playStart = Date()
                
                // Restart playback from the new position
                self.startControllers(with: res, at: seconds)
                self.startClock()
                
                // Manually update the UI-bound currentTime since the clock was just reset
                self.currentTime = seconds
            }
        }
    }

    // Update setSongs to work with the new model
    func setSongs(_ newSongs: [Song]) {
        songs = newSongs
        // Clear cache and failure tracking when songs change
        resourceCache.removeAll()
        failedTrackIndices.removeAll()
    }

    // MARK: ––––– Core playback –––––––––––––––––––––––––––––––––––––––––––
    
    private enum PreloadDirection {
        case forward, backward
    }
    
    /// A helper that plays the current track and then preloads the next one in the specified direction.
    private func playAndPreload(direction: PreloadDirection) async {
        var success = false
        await withCheckedContinuation { continuation in
            Task {
                await playCurrentTrack { result in
                    success = result
                    continuation.resume()
                }
            }
        }

        // If the track failed to load, automatically skip to the next one
        if !success {
            print("⏭️ Track at index \(currentTrackIndex) failed to load, skipping.")
            // Mark this track as failed
            failedTrackIndices.insert(currentTrackIndex)
            // Automatically skip to the next track
            nextTrack(userInitiated: false)
            return // Exit to avoid preloading based on a failed track
        }
        
        // If playback was successful, clear the failure tracking
        failedTrackIndices.removeAll()

        // Preload the next appropriate track in the background
        let preloadIndex: Int
        switch direction {
        case .forward:
            preloadIndex = (currentTrackIndex + 1) % songs.count
        case .backward:
            preloadIndex = (currentTrackIndex - 1 + songs.count) % songs.count
        }
        await loadAndCacheTrack(at: preloadIndex)
    }
    
    /// Plays `songs[currentTrackIndex]`.
    /// If the resource was loaded before we reuse it from `resourceCache`.
    private func playCurrentTrack(completion: @escaping (Bool) -> Void = { _ in }) async {
        // 1. Set loading state to true and stop previous playback
        self.isLoadingTrack = true
        stopControllers()
        stopClock()

        // 2. Use the helper to get the resource for the current track
        guard let resource = await loadAndCacheTrack(at: currentTrackIndex) else {
            // If loading fails, update state and signal failure
            self.isPlaying = false
            self.isLoadingTrack = false
            completion(false)
            return
        }

        // 3. On success, update state and start playback
        self.audioResource = resource
        self.trackDuration = resource.duration / .seconds(1)
        self.accumulated = 0
        self.playStart = Date()
        self.startControllers(with: resource, at: 0)
        self.startClock()
        self.isPlaying = true
        self.isLoadingTrack = false // Done loading

        completion(true) // Signal success
    }
    
    /// Loads a track at a specific index, using the cache if available.
    /// Returns the resource on success or nil on failure.
    @discardableResult
    private func loadAndCacheTrack(at index: Int) async -> AudioFileResource? {
        // Ensure the index is valid
        guard let song = songs[safe: index] else {
            print("❌ Preload failed: Index \(index) is out of bounds.")
            return nil
        }

        let audioURL = song.audioURL

        // 1. Check if it's already in the cache (this is fast, fine for MainActor)
        if let cachedResource = resourceCache[audioURL] {
            return cachedResource
        }
        
        print("⏳ Loading track: '\(song.song)'")

        // 2. ✅ SOLUTION: Call our new non-isolated function to do the heavy work
        //    on a background thread.
        do {
            let resource = try await self.downloadAndCreateResource(for: song)
            
            // 3. The 'await' above returns execution to the MainActor.
            //    It's now safe to update the cache.
            resourceCache[audioURL] = resource
            
            print("✅ Successfully loaded and cached '\(song.song)'")
            return resource

        } catch {
            print("❌ Failed to load and cache track '\(song.song)': \(error)")
            // Mark the track as failed so we can skip it automatically.
            failedTrackIndices.insert(index)
            return nil
        }
    }
    
    // ✅ SOLUTION: This new function is marked 'nonisolated'.
    // It will run on a background thread, not the MainActor.
    nonisolated private func downloadAndCreateResource(for song: Song) async throws -> AudioFileResource {
        let audioURL = song.audioURL
        let ref = Storage.storage().reference(forURL: audioURL)
        
        // This download and subsequent file write will now happen in the background.
        let localURL = try await self.downloadTempFile(from: ref, preferredName: song.song)
        
        let alias = self.sanitiseAlias(URL(string: audioURL)?.lastPathComponent ?? "audio.wav")
        
        // This is often the most intensive part. By running it here, we don't block the UI.
        let resource = try await AudioFileResource(
            contentsOf: localURL,
            withName: alias,
            configuration: .init(shouldLoop: false)
        )
        
        // Clean up the temporary file after we've loaded it into memory.
        try? FileManager.default.removeItem(at: localURL)
        
        return resource
    }

    // ✅ SOLUTION: Mark helper functions used by our new function as 'nonisolated' as well.
    // They don't access any MainActor-protected state, so this is safe.
    nonisolated private func downloadTempFile(from ref: StorageReference,
                                           preferredName: String) async throws -> URL {

        // preserve extension; default to "wav" if none
        let ext = (preferredName as NSString).pathExtension
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "wav" : ext)

        let data = try await ref.data(maxSize: 50 * 1024 * 1024)   // 50 MB cap
        try data.write(to: tmp, options: .atomic) // This synchronous write no longer blocks the main thread
        return tmp
    }
    
    // ✅ SOLUTION: Also mark this as nonisolated.
    nonisolated private func sanitiseAlias(_ fileName: String) -> String {
        let ext  = (fileName as NSString).pathExtension
        let base = ((fileName as NSString).deletingPathExtension)
            .replacingOccurrences(of: "[^A-Za-z0-9_\\-]", with: "_",
                                  options: .regularExpression)
        return "\(base).\(ext)"
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
        if let start = playStart {
            accumulated += Date().timeIntervalSince(start)
        }
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
                guard let self = self, self.isPlaying, let start = self.playStart else { return }

                let elapsed = self.accumulated + Date().timeIntervalSince(start)
                self.currentTime = elapsed

                // When we reach / pass the duration, go to the next track
                if self.trackDuration > 0 && elapsed >= self.trackDuration {
                    self.nextTrack(userInitiated: false)
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
    
    // MARK: - Stop everything
    @MainActor
    func stopAllAudio() {
        stopControllers()
        stopClock()
        isPlaying = false
        isLoadingTrack = false
        resourceCache.removeAll()   // ← optional, if you want a full flush
        failedTrackIndices.removeAll()
    }


    // In SpatialAudioLoader
    nonisolated private func findSpeakers(in root: Entity) -> [Entity] {
        var out: [Entity] = []
        if root.name.hasPrefix("speaker_") { out.append(root) }
        for child in root.children {
            out += findSpeakers(in: child)
        }
        return out
    }
    
    func linearToDB(_ v: Float) -> Float { v <= 0 ? -80 : 20 * log10(v) }
}
