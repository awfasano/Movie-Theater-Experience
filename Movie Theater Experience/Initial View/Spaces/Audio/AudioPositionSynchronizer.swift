//
//  AudioPositionSynchronizer.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 4/25/25.
//

import Foundation
import RealityFoundation
import AVFAudio

// Helper class to synchronize AVAudioPlayer position with RealityKit entity
class AudioPositionSynchronizer {
    weak var entity: Entity?
    private var player: AVAudioPlayer?
    private var updateTimer: Timer?
    private var relativePosition: SIMD3<Float>?
    private var baseVolume: Float = 1.0
    @Published private(set) var currentTrackIndex: Int = 0

    
    init(entity: Entity, relativePosition: SIMD3<Float>? = nil) {
        self.entity = entity
        self.relativePosition = relativePosition
    }
    

    
    func startTracking(player: AVAudioPlayer) {
        self.player = player
        
        // Initial position update
        updateAudioParameters()
        
        // Set up a timer to update audio parameters based on entity position
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateAudioParameters()
        }
    }
    
    // Add this method to match what's being called in SpatialAudioLoader
    func setBaseVolume(_ volume: Float) {
        self.baseVolume = volume
        updateAudioParameters()
    }
    
    // Add this method to match what's being called in SpatialAudioLoader
    func updateVolume(_ volume: Float) {
        self.baseVolume = volume
        updateAudioParameters()
    }
    
    func updateRelativePosition(_ newPosition: SIMD3<Float>?) {
        self.relativePosition = newPosition
        updateAudioParameters()
    }
    
    private func updateAudioParameters() {
        guard let entity = entity, let player = player else {
            stopTracking()
            return
        }
        
        // Get entity's position in world space
        let worldTransform = entity.convert(transform: .init(), to: nil)
        let position = worldTransform.translation
        
        // Calculate distance to listener
        // If we have a relative position from seat, use that distance
        // Otherwise calculate distance to camera/listener (assuming camera is at origin)
        let distance: Float
        let pan: Float
        
        if let relativePos = relativePosition {
            // Use the pre-calculated relative position from the seat
            distance = length(relativePos)
            
            // Calculate pan based on the X component of the relative position
            // Normalize to range -1.0 to 1.0
            let maxPanDistance: Float = 5.0
            pan = max(-1.0, min(1.0, relativePos.x / maxPanDistance))
        } else {
            // Fall back to distance from origin/camera
            let cameraPosition = SIMD3<Float>(0, 0, 0)
            distance = length(position - cameraPosition)
            
            // Simple left/right panning based on world X position
            let maxPanDistance: Float = 5.0
            pan = max(-1.0, min(1.0, position.x / maxPanDistance))
        }
        
        // Apply distance-based attenuation
        let maxDistance: Float = 10.0  // Maximum audible distance
        let rolloffFactor: Float = 1.0 // How quickly volume drops with distance
        
        if distance <= maxDistance {
            // Inverse square law attenuation formula (more realistic than linear)
            let distanceVolume = 1.0 / (1.0 + rolloffFactor * (distance * distance) / (maxDistance * maxDistance))
            
            // Combine baseVolume (user-controlled) with distance-based attenuation
            let finalVolume = baseVolume * max(0.0, min(1.0, Float(distanceVolume)))
            player.volume = finalVolume
        } else {
            player.volume = 0.0
        }
        
        // Note: AVAudioPlayer doesn't directly support panning
        // In a more advanced implementation, you would use AVAudio3DMixing
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
