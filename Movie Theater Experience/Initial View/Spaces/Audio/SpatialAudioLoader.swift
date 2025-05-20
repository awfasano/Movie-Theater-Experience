//
//  SpatialAudioLoader.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 4/25/25.
//

import Foundation
import FirebaseStorage
import RealityKit
import AVFoundation

struct SpatialAudioLoader {
    // Reference to Firebase Storage
    private let storage = Storage.storage()
    // Track audio players for streaming
    private var streamingPlayers: [String: AVAudioPlayer] = [:]
    
    // Main function to handle audio setup for a space
    func loadAudioForSpace(spaceEntity: Entity, spaceName: String, completion: @escaping (Bool) -> Void) {
        guard let speakersGroup = spaceEntity.findEntity(named: "speakers") else {
            print("⚠️ No speakers group found in space entity")
            completion(false)
            return
        }
        
        print("✅ Found speakers group in entity: \(speakersGroup.name)")
        
        // Find all speaker entities
        let speakerEntities = findAllSpeakerEntities(in: speakersGroup)
        if speakerEntities.isEmpty {
            print("⚠️ No speaker entities found under speakers group")
            completion(false)
            return
        }
        
        print("🔈 Found \(speakerEntities.count) speaker entities")
        
        // Create a dispatch group to track completion of all audio loads
        let group = DispatchGroup()
        var success = true
        
        // Process each speaker entity
        for speakerEntity in speakerEntities {
            // Extract speaker number from entity name (e.g., "speaker_1" -> "1")
            let speakerName = speakerEntity.name
            guard let speakerNumber = speakerName.split(separator: "_").last else {
                print("⚠️ Could not extract speaker number from: \(speakerName)")
                continue
            }
            
            // Determine audio file path in storage
            let audioPath = "Music/\(spaceName)/speaker_\(speakerNumber).mp3"
            
            group.enter()
            
            // Get file metadata to check size
            let storageRef = storage.reference().child(audioPath)
            storageRef.getMetadata { metadata, error in
                if let error = error {
                    print("❌ Error getting metadata: \(error.localizedDescription)")
                    success = false
                    group.leave()
                    return
                }
                
                guard let metadata = metadata else {
                    print("❌ No metadata available for: \(audioPath)")
                    success = false
                    group.leave()
                    return
                }
                
                // Decide whether to stream or download based on file size
                // 10MB threshold - adjust as needed
                let fileSizeThreshold: Int64 = 10 * 1024 * 1024
                
                if metadata.size > fileSizeThreshold {
                    // Large file - use streaming approach
                    self.setupStreamingAudio(for: speakerEntity,
                                            path: audioPath,
                                            entityId: speakerEntity.id.uuidString) { streamSuccess in
                        if !streamSuccess {
                            success = false
                        }
                        group.leave()
                    }
                } else {
                    // Smaller file - use standard RealityKit audio component
                    self.loadAudioFromStorage(path: audioPath) { audioResource in
                        if let audioResource = audioResource {
                            self.configureSpatialAudio(for: speakerEntity, with: audioResource)
                            print("✅ Successfully configured audio for: \(speakerName)")
                        } else {
                            print("❌ Failed to load audio for: \(speakerName) from path: \(audioPath)")
                            success = false
                        }
                        group.leave()
                    }
                }
            }
        }
        
        // Notify completion when all audio files are processed
        group.notify(queue: .main) {
            completion(success)
        }
    }
    
    // Streaming approach for larger audio files
    private func setupStreamingAudio(for entity: Entity,
                                    path: String,
                                    entityId: String,
                                    completion: @escaping (Bool) -> Void) {
        print("🎵 Setting up streaming audio for: \(entity.name) from path: \(path)")
        
        let storageRef = storage.reference().child(path)
        
        // Get download URL for the file
        storageRef.downloadURL { url, error in
            guard let fileURL = url, error == nil else {
                print("❌ Error getting download URL: \(error?.localizedDescription ?? "unknown error")")
                completion(false)
                return
            }
            
            // Create an AVAudioSession for background playback
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("❌ Failed to set up audio session: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            // Create AudioPositionSynchronizer to handle position updates
            let positionSynchronizer = AudioPositionSynchronizer(entity: entity)
            
            // Download a small portion initially to start playback quickly
            let downloadTask = URLSession.shared.dataTask(with: fileURL) { data, response, error in
                guard let data = data, error == nil else {
                    print("❌ Error downloading audio data: \(error?.localizedDescription ?? "unknown error")")
                    completion(false)
                    return
                }
                
                do {
                    // Create AVAudioPlayer with the downloaded data
                    let audioPlayer = try AVAudioPlayer(data: data)
                    audioPlayer.prepareToPlay()
                    
                    // Store the player for later reference
                    self.streamingPlayers[entityId] = audioPlayer
                    
                    // Configure audio settings
                    audioPlayer.volume = 1.0
                    audioPlayer.numberOfLoops = -1 // Loop indefinitely
                    audioPlayer.play()
                    
                    // Set up position synchronizer
                    positionSynchronizer.startTracking(player: audioPlayer)
                    
                    print("✅ Successfully started streaming audio for: \(entity.name)")
                    completion(true)
                } catch {
                    print("❌ Error creating audio player: \(error.localizedDescription)")
                    completion(false)
                }
            }
            
            downloadTask.resume()
        }
    }
    
    // Stop streaming for an entity
    func stopStreamingAudio(for entityId: String) {
        if let player = streamingPlayers[entityId] {
            player.stop()
            streamingPlayers.removeValue(forKey: entityId)
            print("🛑 Stopped streaming audio for entity ID: \(entityId)")
        }
    }
    
    // Stop all streaming audio
    func stopAllStreamingAudio() {
        for (entityId, player) in streamingPlayers {
            player.stop()
            print("🛑 Stopped streaming audio for entity ID: \(entityId)")
        }
        streamingPlayers.removeAll()
    }
    
    // Rest of the methods remain the same as in your previous implementation...
    // findAllSpeakerEntities, findSpeakerEntitiesDeep, loadAudioFromStorage, configureSpatialAudio
    
    // Find all speaker entities in a parent entity
    private func findAllSpeakerEntities(in parent: Entity) -> [Entity] {
        var speakers: [Entity] = []
        
        // Regular speaker entities (direct children)
        for child in parent.children where child.name.hasPrefix("speaker_") {
            speakers.append(child)
        }
        
        // If no direct children found, try deep search
        if speakers.isEmpty {
            speakers = findSpeakerEntitiesDeep(in: parent)
        }
        
        return speakers
    }
    
    // Recursive deep search for speaker entities
    private func findSpeakerEntitiesDeep(in parent: Entity) -> [Entity] {
        var speakers: [Entity] = []
        
        for child in parent.children {
            if child.name.hasPrefix("speaker_") {
                speakers.append(child)
            }
            
            // Recursively search in children
            let childSpeakers = findSpeakerEntitiesDeep(in: child)
            speakers.append(contentsOf: childSpeakers)
        }
        
        return speakers
    }
    
    // Load audio from Firebase Storage
    private func loadAudioFromStorage(path: String, completion: @escaping (AudioResource?) -> Void) {
        let storageRef = storage.reference().child(path)
        
        // Create a temporary local URL for the downloaded file
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        
        storageRef.write(toFile: localURL) { url, error in
            guard let fileURL = url, error == nil else {
                print("❌ Error downloading audio file: \(error?.localizedDescription ?? "unknown error")")
                completion(nil)
                return
            }
            
            // Try to load the audio as a resource
            Task {
                do {
                    let audioResource = try await AudioResource(contentsOf: fileURL)
                    completion(audioResource)
                } catch {
                    print("❌ Error creating audio resource: \(error.localizedDescription)")
                    completion(nil)
                }
                
                // Clean up the temporary file
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
    
    // Configure spatial audio for an entity
    private func configureSpatialAudio(for entity: Entity, with audioResource: AudioResource) {
        // Check if the entity already has a spatial audio component
        if var spatialAudio = entity.components[SpatialAudioComponent.self] {
            // Update existing component
            spatialAudio.resource = audioResource
            
            // Configure optimal settings
            spatialAudio.gain = 1.0  // Default gain (in linear scale)
            spatialAudio.directLevel = 1.0  // Direct sound level (linear)
            spatialAudio.reverbLevel = 0.3  // Reverb level (linear)
            spatialAudio.isLooping = true   // Loop audio
            spatialAudio.isPlaying = true   // Start playing automatically
            spatialAudio.focus = 1.0        // Direct/ambient balance (1.0 = fully directional)
            spatialAudio.rolloffFactor = 1.0 // Distance attenuation factor
            
            // Apply updated component
            entity.components[SpatialAudioComponent.self] = spatialAudio
            print("🔊 Updated spatial audio component for: \(entity.name)")
        } else {
            // Create new component
            var spatialAudio = SpatialAudioComponent(source: audioResource)
            
            // Configure optimal settings
            spatialAudio.gain = 1.0
            spatialAudio.directLevel = 1.0
            spatialAudio.reverbLevel = 0.3
            spatialAudio.isLooping = true
            spatialAudio.isPlaying = true
            spatialAudio.focus = 1.0
            spatialAudio.rolloffFactor = 1.0
            
            // Add component to entity
            entity.components[SpatialAudioComponent.self] = spatialAudio
            print("🔊 Created new spatial audio component for: \(entity.name)")
        }
    }
}

// Helper class to synchronize AVAudioPlayer position with RealityKit entity
class AudioPositionSynchronizer {
    private weak var entity: Entity?
    private var player: AVAudioPlayer?
    private var updateTimer: Timer?
    
    init(entity: Entity) {
        self.entity = entity
    }
    
    func startTracking(player: AVAudioPlayer) {
        self.player = player
        
        // Set up a timer to update audio parameters based on entity position
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateAudioParameters()
        }
    }
    
    private func updateAudioParameters() {
        guard let entity = entity, let player = player else {
            stopTracking()
            return
        }
        
        // Get entity's position in world space
        let worldTransform = entity.convert(transform: .init(), to: nil)
        let position = worldTransform.translation
        
        // Calculate distance to camera/listener (assuming camera is at origin for simplicity)
        // In a real implementation, you'd get the actual camera position
        let cameraPosition = SIMD3<Float>(0, 0, 0)
        let distance = length(position - cameraPosition)
        
        // Apply distance-based attenuation
        let maxDistance: Float = 10.0  // Maximum audible distance
        let rolloffFactor: Float = 1.0 // How quickly volume drops with distance
        
        if distance <= maxDistance {
            // Linear attenuation formula
            let volume = 1.0 - (distance / maxDistance) * rolloffFactor
            player.volume = max(0.0, min(1.0, Float(volume)))
        } else {
            player.volume = 0.0
        }
        
        // Update stereo panning based on left/right position
        // Simplistic approach - more sophisticated spatial audio would use HRTF
        let maxPan: Float = 1.0
        let normalizedX = position.x / maxDistance
        let pan = max(-maxPan, min(maxPan, normalizedX))
        
        // Note: AVAudioPlayer doesn't directly support panning
        // For true spatial audio with panning, consider AVAudio3DMixing with AVAudioEnvironmentNode
    }
    
    func stopTracking() {
        updateTimer?.invalidate()
        updateTimer = nil
        player = nil
    }
    
    deinit {
        stopTracking()
    }
}
