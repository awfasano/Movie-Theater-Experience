import SwiftUI
import RealityKit

@available(visionOS 2.0, *)
class TheatreEntityWrapper: ObservableObject {
    static let shared = TheatreEntityWrapper()
    @Published var entity: Entity?
    @Published var videoPlayerManager: VideoPlayerManager?  // Add this line
    @AppStorage("showEmojis") private var showEmojis = true
    
    private var lastEmissionTime: Date?
    private var emissionTimer: Timer?
    private let cooldownPeriod: TimeInterval = 2 // 2 second cooldown
    
    init() {} // Keep the singleton pattern
    
    func setEmojiVisibility(_ isVisible: Bool) {
        showEmojis = isVisible
        
        // Update the visibility of the emoji entity without triggering an emission
        if let emojiEntity = entity?.findEntity(named: "VolumetericEmoji") {
            // Update the visibility state
            emojiEntity.isEnabled = isVisible
            
            // If hiding emojis, stop any ongoing emissions
            if !isVisible {
                stopEmission()
            }
        }
    }
    
    func updateVolumetricEmojiTexture(with imageName: String) {
        // First check if we're showing emojis at all
        guard showEmojis else {
            print("Emoji display is disabled, skipping emission")
            return
        }
        
        // Check if this is a direct user action vs. a nav bar interaction
        guard let lastEmission = lastEmissionTime,
              Date().timeIntervalSince(lastEmission) < cooldownPeriod else {
            // If we're outside the cooldown period, this might be a nav interaction
            // Skip the emission unless it's a direct emoji button press
            if Date().timeIntervalSince(lastEmissionTime ?? Date.distantPast) < 0.1 {
                print("Skipping emission due to potential nav interaction")
                return
            }
            
            // Continue with emission for direct user actions
            proceedWithEmission(imageName: imageName)
            return
        }
        
        print("Skipping emission due to cooldown")
    }
    
    private func proceedWithEmission(imageName: String) {
        // Find the VolumetricEmoji entity recursively
        guard let emojiEntity = entity?.findEntity(named: "VolumetericEmoji") else {
            print("Could not find VolumetericEmoji entity")
            return
        }
        
        // Find the particle emitter component
        guard var particleEmitter = emojiEntity.components[ParticleEmitterComponent.self] as? ParticleEmitterComponent else {
            print("No particle emitter component found")
            return
        }
        
        // Load directly from main bundle/assets
        guard let image = UIImage(named: imageName),
              let cgImage = image.cgImage else {
            print("Failed to load image: \(imageName)")
            return
        }
        
        do {
            let textureResource = try TextureResource.generate(from: cgImage,
                                                             options: .init(semantic: .normal))
            
            // Update the emitter image and birth rate
            particleEmitter.mainEmitter.image = textureResource
            particleEmitter.mainEmitter.birthRate = 200
            
            // Remove old emitter and add updated one
            emojiEntity.components.remove(ParticleEmitterComponent.self)
            emojiEntity.components.set(particleEmitter)
            
            // Update last emission time
            lastEmissionTime = Date()
            
            // Set timer to stop emission
            emissionTimer?.invalidate()
            emissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.stopEmission()
            }
            
            print("Successfully updated emitter with image: \(imageName)")
            
        } catch {
            print("Failed to generate texture resource: \(error)")
        }
    }
    
    private func stopEmission() {
        guard let emojiEntity = entity?.findEntity(named: "VolumetericEmoji"),
              var particleEmitter = emojiEntity.components[ParticleEmitterComponent.self] as? ParticleEmitterComponent else {
            return
        }
        
        particleEmitter.mainEmitter.birthRate = 0
        emojiEntity.components.set(particleEmitter)
        print("Stopped emission")
    }
    
    deinit {
        emissionTimer?.invalidate()
    }
}

// Helper extension to find entities by name
extension Entity {
    func findEntity(named name: String) -> Entity? {
        if self.name == name {
            return self
        }
        
        for child in children {
            if let found = child.findEntity(named: name) {
                return found
            }
        }
        
        return nil
    }
}
