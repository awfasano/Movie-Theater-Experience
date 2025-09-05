// FIXED: AmbientAudioManager.swift - Implemented a persistent cache to prevent resource conflicts
import Foundation
import RealityKit
import AVFoundation

class AmbientAudioManager {
    static let shared = AmbientAudioManager()

    private var audioControllers: [Entity: AudioPlaybackController] = [:]
    private var pendingVolumes: [Entity: Float] = [:]

    private init() {}

    // MARK: - Caching Logic

    /// Returns a URL for the cached audio file if it exists.
    private func getCachedURL(for remoteURL: URL) -> URL? {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            print("❌ Could not get caches directory.")
            return nil
        }
        
        // Create a consistent, safe filename from the remote URL
        let fileName = remoteURL.lastPathComponent
        let localURL = cachesDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: localURL.path) {
            print("✅ Found cached audio file at: \(localURL.path)")
            return localURL
        }
        
        return nil
    }
    
    /// Downloads and saves the audio file to the cache.
    private func downloadAndCacheAudio(from remoteURL: URL) async throws -> URL {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw AmbientAudioError.cacheError
        }
        
        let fileName = remoteURL.lastPathComponent
        let localURL = cachesDirectory.appendingPathComponent(fileName)

        print("🎵 Downloading audio to cache from: \(remoteURL.absoluteString)")
        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        
        try data.write(to: localURL)
        print("💾 Saved cached audio file: \(localURL.path)")
        
        return localURL
    }

    /// Sets up ambient audio for a Root entity from a Firebase Storage URL
    func setupAmbientAudio(
        for rootEntity: Entity,
        audioURLString: String
    ) async throws {
        guard let remoteURL = URL(string: audioURLString) else {
            print("❌ Invalid URL format: \(audioURLString)")
            throw AmbientAudioError.invalidURL
        }
        
        // Don't re-setup if a controller already exists for this entity.
        // This prevents issues if setup is called multiple times.
        if audioControllers[rootEntity] != nil {
            print("✅ Audio is already set up for this entity. Skipping.")
            return
        }

        do {
            // 1. Check for a cached file or download it.
            let audioFileURL: URL
            if let cachedURL = getCachedURL(for: remoteURL) {
                audioFileURL = cachedURL
            } else {
                audioFileURL = try await downloadAndCacheAudio(from: remoteURL)
            }

            // 2. Try to load the audio resource from the stable cached URL.
            let audioResource = try await AudioFileResource.load(
                contentsOf: audioFileURL,
                withName: remoteURL.lastPathComponent // The name is now consistently tied to the same file path.
            )
            print("✅ Successfully loaded AudioFileResource from cache.")
            
            // 3. Create and add ambient audio component.
            let ambientComponent = ChannelAudioComponent()
            rootEntity.components.set(ambientComponent)

            // 4. Prepare the audio controller.
            let controller = await rootEntity.prepareAudio(audioResource)
            audioControllers[rootEntity] = controller
            
            print("✅ Ambient audio component added and controller prepared for \(await rootEntity.name)")

        } catch {
            print("❌ Failed to load audio: \(error)")
            print("🔍 Error details: \(error.localizedDescription)")
            throw AmbientAudioError.resourceLoadFailed
        }
    }

    /// Start playing ambient audio
    func play(entity: Entity) {
        guard let controller = audioControllers[entity] else {
            print("⚠️ No audio controller found for entity - call setupAmbientAudio first")
            return
        }
        
        let volumeToApply: Float
        if let pendingVolume = pendingVolumes[entity] {
            volumeToApply = pendingVolume
            pendingVolumes.removeValue(forKey: entity)
            print("🔊 Applied pending volume: \(pendingVolume) dB")
        } else {
            volumeToApply = Self.percentageToDecibels(50.0)
            print("🔊 Applied default volume: \(volumeToApply) dB (50%)")
        }
        
        controller.gain = Audio.Decibel(volumeToApply)
        controller.play()
        print("▶️ Started ambient audio playback")
    }

    /// Pause ambient audio
    func pause(entity: Entity) {
        if let controller = audioControllers[entity] {
            controller.pause()
            print("⏸ Paused ambient audio playback")
        }
    }

    /// Stop and clean up ambient audio
    func stop(entity: Entity) {
        if let controller = audioControllers[entity] {
            controller.stop()
            audioControllers.removeValue(forKey: entity)
            pendingVolumes.removeValue(forKey: entity)
            print("⏹ Stopped and removed ambient audio controller.")
        }
        // No need to clean up the cached file anymore.
    }
    
    /// Update volume (in decibels)
    func setVolume(_ gainDB: Float, for entity: Entity) {
        if let controller = audioControllers[entity] {
            controller.gain = Audio.Decibel(gainDB)
            print("🔊 Set volume to \(gainDB) dB")
        } else {
            pendingVolumes[entity] = gainDB
            print("📝 Stored pending volume: \(gainDB) dB")
        }
    }

    static func percentageToDecibels(_ percentage: Float) -> Float {
        guard percentage > 0 else { return -200 } // Effectively silent
        let normalized = percentage / 100.0
        return (normalized * 20.0) - 20
    }
}

enum AmbientAudioError: Error {
    case invalidURL
    case resourceLoadFailed
    case entityNotFound
    case cacheError
}

