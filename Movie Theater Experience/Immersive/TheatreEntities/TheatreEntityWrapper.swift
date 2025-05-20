import SwiftUI
import RealityKit
import RealityKitContent

@available(visionOS 2.0, *)
class TheatreEntityWrapper: ObservableObject {
    static let shared = TheatreEntityWrapper()
    
    private let videoSyncService = VideoSyncService.shared

    
    // Lock for thread-safe entity operations
    private let entityLock = NSLock()
    
    // Published properties
    @Published private(set) var entity: Entity?
    @Published var screenEntity: ModelEntity?
    @Published var videoPlayerManager: VideoPlayerManager?
    @AppStorage("showEmojis") private var showEmojis = true
    @Published private(set) var isEmitting = false
    @Published private var spaceEntity: Entity?

    
    init() {
        print("📽️ TheatreEntityWrapper initialized")
    }
    
    // MARK: - Entity Management
    
    func setEntity(_ newEntity: Entity?) {
        entityLock.lock()
        defer { entityLock.unlock() }
        
        Task { @MainActor in
            self.entity = newEntity
            self.screenEntity = findScreenEntity(in: newEntity) // Track screen entity
        }
    }
    
    func setSpaceEntity(_ entity: Entity) {
        spaceEntity = entity
    }
    
    func getSpaceEntity() -> Entity? {
        return spaceEntity
    }
    
    func removeEntity() async {
        await MainActor.run {
            if let existingEntity = entity {
                existingEntity.removeFromParent()
                self.entity = nil
            }
        }
    }
    
    // MARK: - Cleanup
    // In /Immersive/TheatreEntities/TheatreEntityWrapper.swift

    func cleanup() async {
        print("🧹 Starting TheatreEntityWrapper cleanup")

        // Hide the screen entity before removing
        await MainActor.run {
            if let screenEntity = self.screenEntity {
                screenEntity.isEnabled = false
                screenEntity.removeFromParent()
                self.screenEntity = nil
            }
        }

        // Safely check for the manager. Note: Accessing a @Published property
        // from a background thread can cause data races. This cleanup function
        // should ideally be a @MainActor function if it's not already.
        // For now, this structure will resolve the compiler error.
        if let manager = self.videoPlayerManager {
            
            // 1. Perform the async operation first.
            // The 'switchToView' function is already marked @MainActor, so this call
            // will safely execute on the main thread, and 'cleanup' will wait for it.
            await videoSyncService.switchToView(.none)
            
            // 2. Perform the remaining synchronous cleanup operations in their own
            //    MainActor.run block. The closure here is now synchronous.
            await MainActor.run {
                print("🧹 Clearing video player manager resources.")
                manager.clearAllResources()
                self.videoPlayerManager = nil
            }
        }

        await removeEntity()

        print("✅ TheatreEntityWrapper cleanup completed")
    }

    
    // MARK: - Emoji Management
    
    func setEmojiVisibility(_ isVisible: Bool) {
        entityLock.lock()
        defer { entityLock.unlock() }
        
        print("👁️ Setting emoji visibility to: \(isVisible)")
        showEmojis = isVisible
        
        Task { @MainActor in
            // Update the visibility of the emoji entity without triggering an emission
            if let emojiEntity = entity?.findEntity(named: "VolumetericEmoji") {
                // Update the visibility state
                emojiEntity.isEnabled = isVisible
                
                // If hiding emojis, stop any ongoing emissions
                if !isVisible {
                    await stopEmission()
                }
            }
        }
    }
    
    private func findScreenEntity(in entity: Entity?) -> ModelEntity? {
        guard let entity = entity else { return nil }
        
        for child in entity.children {
            if let modelEntity = child as? ModelEntity {
                return modelEntity
            }
        }
        return nil
    }
    
    /// Call this to update the emoji texture and trigger a new emission.
    func updateVolumetricEmojiTexture(with imageName: String) {
        entityLock.lock()
        defer { entityLock.unlock() }
        
        // First check if we're showing emojis at all
        guard showEmojis else {
            print("🚫 Emoji display is disabled, skipping emission")
            return
        }
        
        Task { @MainActor in
            print("🎯 Starting emoji emission for: \(imageName)")
            await proceedWithEmission(imageName: imageName)
        }
    }
    
    private func printEntityHierarchy(_ entity: Entity, level: Int = 0) {
        let indent = String(repeating: "  ", count: level)
        print("\(indent)📦 \(entity.name)")
        
        // Print components
        for component in entity.components {
            print("\(indent)  🔧 \(type(of: component))")
        }
        
        // Recursively print children
        for child in entity.children {
            printEntityHierarchy(child, level: level + 1)
        }
    }
    
    // MARK: - Emission
    
    private func proceedWithEmission(imageName: String) async {
        // Stop any ongoing emission first
        await stopEmission()
        
        guard let entity = entity else {
            print("❌ No root entity found")
            return
        }
        
        guard let emojiEntity = entity.findEntity(named: "VolumetericEmoji") else {
            print("❌ Could not find VolumetericEmoji entity")
            return
        }
        
        // Pre-load your new texture outside MainActor.run
        guard let image = UIImage(named: imageName),
              let cgImage = image.cgImage else {
            print("❌ Failed to load image: \(imageName)")
            return
        }
        
        do {
            let textureResource = try await TextureResource(image: cgImage, options: .init(semantic: .normal))
            
            // Everything that touches `emojiEntity.components` must be on MainActor
            try await MainActor.run {
                // 1) Check if an old emitter exists
                guard let oldEmitter = emojiEntity.components[ParticleEmitterComponent.self] else {
                    print("❌ No ParticleEmitterComponent found on VolumetericEmoji")
                    return
                }
                
                // 2) Remove it to reset the one-shot
                emojiEntity.components.remove(ParticleEmitterComponent.self)
                
                // 3) Make a mutable copy
                var updatedEmitter = oldEmitter
                
                // 4) Update the texture or any other properties
                updatedEmitter.mainEmitter.image = textureResource
                // e.g. updatedEmitter.mainEmitter.birthRate = 10
                // e.g. updatedEmitter.mainEmitter.size = 5.0
                
                updatedEmitter.isEmitting = true
                updatedEmitter.timing = .once(
                    warmUp: 0.0,
                    emit: .init(duration: 3.0)
                )
                
                // 5) Re-assign the updated emitter
                emojiEntity.components[ParticleEmitterComponent.self] = updatedEmitter
                
                // Make sure the entity is enabled
                emojiEntity.isEnabled = true
                
                // Mark that we're emitting
                isEmitting = true
                print("✅ Reusing & restarting built-in emitter with image: \(imageName)")
            }
            
            // Wait for 3 seconds + 1 second buffer before stopping automatically
            try? await Task.sleep(for: .seconds(4.0))
            
            // Stop if it's still active
            if isEmitting {
                await stopEmission()
            }
            
        } catch {
            print("❌ Emission failed: \(error)")
            await stopEmission()
        }
    }


    
    /// Safely stops the current emission if it's active.
    private func stopEmission() async {
        await MainActor.run {
            guard let emojiEntity = entity?.findEntity(named: "VolumetericEmoji") else {
                return
            }
            
            guard let particleEmitter = emojiEntity.components[ParticleEmitterComponent.self] else {
                return
            }
            
            guard isEmitting else {
                // If we are not actively emitting, do nothing
                return
            }
            
            // Update the emitter to stop emitting new particles
            var updatedEmitter = particleEmitter
            updatedEmitter.isEmitting = false
            
            // Optionally set birthRate = 0 to ensure immediate stop of new particles
            // updatedEmitter.mainEmitter.birthRate = 0
            
            emojiEntity.components[ParticleEmitterComponent.self] = updatedEmitter
            
            isEmitting = false
            print("🛑 Emission stopped")
        }
    }
    
    deinit {
        print("♻️ TheatreEntityWrapper deinit")
        Task {
            await cleanup()
        }
    }
    
    // MARK: - Video Screen Helpers
    /// Creates (or returns) a dedicated plane sized to the screen mesh.
    /// Always called on MainActor.
    @MainActor
    func videoPlane(for screenMesh: ModelEntity) -> ModelEntity {
        if let cached = screenMesh.findEntity(named: "VideoPlane") as? ModelEntity {
            return cached
        }

        let bounds = screenMesh.model?.mesh.bounds ?? .init()
        let width  = bounds.extents.x
        let height = bounds.extents.y

        // Plane thickness is ≈0 so Z‑fighting is avoided
        let planeMesh = MeshResource.generatePlane(width: width,
                                                   height: height,
                                                   cornerRadius: 0)
        
        let plane     = ModelEntity(mesh: planeMesh,
                                    materials: [UnlitMaterial(color: .black)])
        plane.name    = "VideoPlane"

        // Position the plane flush with the front face of the mesh
        let frontZ = bounds.center.z + bounds.extents.z * 0.51
        plane.position = [bounds.center.x, bounds.center.y, frontZ]

        // Clamp rendering order so it always draws on top of the mesh
       // plane.renderingOrder = .

        screenMesh.addChild(plane)
        return plane
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
