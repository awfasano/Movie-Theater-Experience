// AmbientAudioManager.swift
// Persistent cache + safe ambient playback (RealityKit-compatible API)

import Foundation
import RealityKit
import AVFoundation

final class AmbientAudioManager {
    static let shared = AmbientAudioManager()

    // Controllers per entity
    private var audioControllers: [Entity: AudioPlaybackController] = [:]
    private var pendingVolumes: [Entity: Float] = [:]
    private var isPlaying: [Entity: Bool] = [:]  // Track playback state

    private init() {}

    // MARK: - Caching

    /// Returns a URL for the cached audio file if it exists.
    private func getCachedURL(for remoteURL: URL) -> URL? {
        guard let localURL = try? makeLocalURL(for: remoteURL) else {
            return nil
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            print("✅ Found cached audio file at: \(localURL.path)")
            return localURL
        }
        return nil
    }

    /// Downloads and saves the audio file to the cache.
    private func downloadAndCacheAudio(from remoteURL: URL) async throws -> URL {
        let localURL = try makeLocalURL(for: remoteURL)

        print("🎵 Downloading audio to cache from: \(remoteURL.absoluteString)")
        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        try data.write(to: localURL, options: [.atomic])
        print("💾 Saved cached audio file: \(localURL.path)")

        return localURL
    }

    // MARK: - Setup

    /// Sets up ambient audio for a Root entity from a Firebase Storage URL.
    /// - Parameters:
    ///   - rootEntity: The entity to attach audio to.
    ///   - audioURLString: Firebase Storage (or remote) URL string.
    ///   - defaultVolumePercent: 0–100 scale; applied on first play.
    func setupAmbientAudio(
        for rootEntity: Entity,
        audioURLString: String,
        defaultVolumePercent: Float = 50
    ) async throws {
        guard let remoteURL = URL(string: audioURLString) else {
            print("❌ Invalid URL format: \(audioURLString)")
            throw AmbientAudioError.invalidURL
        }

        // Avoid re-setup for same entity
        if audioControllers[rootEntity] != nil {
            print("✅ Audio is already set up for this entity. Skipping.")
            return
        }

        // Prepare system audio session (best-effort; don't crash on failure)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        do {
            // 1) Use cache if available; otherwise download.
            let audioFileURL: URL
            if let cachedURL = getCachedURL(for: remoteURL) {
                audioFileURL = cachedURL
            } else {
                audioFileURL = try await downloadAndCacheAudio(from: remoteURL)
            }

            // 2) Load the audio resource with looping configuration
            var configuration = AudioFileResource.Configuration()
            configuration.shouldLoop = true
            
            let audioResource = try await AudioFileResource(
                contentsOf: audioFileURL,
                withName: remoteURL.lastPathComponent,
                configuration: configuration
            )

            print("✅ Successfully loaded AudioFileResource from cache or download with looping enabled.")

            // 3) Add an audio channel so the controller can play on the entity.
            let channel = ChannelAudioComponent()
            await rootEntity.components.set(channel)

            // 4) Prepare controller and store it.
            let controller = await rootEntity.prepareAudio(audioResource)
            audioControllers[rootEntity] = controller

            // Stage default volume to apply on first play()
            pendingVolumes[rootEntity] = Self.percentageToDecibels(defaultVolumePercent)
            
            // Initialize playback state
            isPlaying[rootEntity] = false

            print("✅ Ambient audio component added and controller prepared for \(await rootEntity.name)")

        } catch {
            print("❌ Failed to load audio: \(error)")
            print("🔍 Error details: \(error.localizedDescription)")
            throw AmbientAudioError.resourceLoadFailed
        }
    }

    // MARK: - Controls

    /// Start playing ambient audio
    func play(entity: Entity) {
        guard let controller = audioControllers[entity] else {
            print("⚠️ No audio controller found for entity - call setupAmbientAudio first")
            return
        }

        let volumeToApply: Float
        if let pendingVolume = pendingVolumes.removeValue(forKey: entity) {
            volumeToApply = pendingVolume
            print("🔊 Applied pending volume: \(pendingVolume) dB")
        } else {
            volumeToApply = Self.percentageToDecibels(50.0)
            print("🔊 Applied default volume: \(volumeToApply) dB (50%)")
        }

        controller.gain = Audio.Decibel(volumeToApply)
        controller.play()
        isPlaying[entity] = true
        print("▶️ Started ambient audio playback with automatic looping")
    }

    /// Pause ambient audio
    func pause(entity: Entity) {
        if let controller = audioControllers[entity] {
            controller.pause()
            isPlaying[entity] = false
            print("⏸ Paused ambient audio playback")
        }
    }

    /// Stop and clean up ambient audio
    func stop(entity: Entity) {
        if let controller = audioControllers[entity] {
            controller.stop()
            audioControllers.removeValue(forKey: entity)
            pendingVolumes.removeValue(forKey: entity)
            isPlaying.removeValue(forKey: entity)
            print("⏹ Stopped and removed ambient audio controller.")
        }
        // Cached file is intentionally retained.
    }

    /// Update volume (in decibels)
    func setVolume(_ gainDB: Float, for entity: Entity) {
        if let controller = audioControllers[entity] {
            // Only apply volume if audio is currently playing
            if isPlaying[entity] == true {
                controller.gain = Audio.Decibel(gainDB)
                print("🔊 Set volume to \(gainDB) dB")
            } else {
                // Store as pending volume if not playing
                pendingVolumes[entity] = gainDB
                print("📝 Stored pending volume: \(gainDB) dB (audio not playing)")
            }
        } else {
            pendingVolumes[entity] = gainDB
            print("📝 Stored pending volume: \(gainDB) dB")
        }
    }
    
    /// Check if audio is currently playing for an entity
    func isAudioPlaying(for entity: Entity) -> Bool {
        return isPlaying[entity] ?? false
    }

    // MARK: - Helpers

    static func percentageToDecibels(_ percentage: Float) -> Float {
        guard percentage > 0 else { return -200 } // Effectively silent
        let normalized = max(0, min(1, percentage / 100.0))
        return (normalized * 20.0) - 20.0
    }
}

// MARK: - Errors

enum AmbientAudioError: Error {
    case invalidURL
    case resourceLoadFailed
    case entityNotFound
    case cacheError
}
    /// Creates the destination URL inside the app's caches directory.
    private func makeLocalURL(for remoteURL: URL) throws -> URL {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw AmbientAudioError.cacheError
        }

        let audioCacheDirectory = cachesDirectory.appendingPathComponent("Spaces/ambient_audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: audioCacheDirectory.path) {
            try FileManager.default.createDirectory(at: audioCacheDirectory, withIntermediateDirectories: true)
        }

        // Firebase download URLs percent-decode to include path separators (e.g. "Spaces/ambient_audio/foo.mp3")
        // which would create unintended subdirectories. Flatten to a single filename.
        let sanitizedName = remoteURL.lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fileName = sanitizedName.isEmpty ? UUID().uuidString : sanitizedName
        return audioCacheDirectory.appendingPathComponent(fileName)
    }
