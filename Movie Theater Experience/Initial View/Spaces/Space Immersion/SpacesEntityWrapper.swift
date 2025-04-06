// SpacesEntityWrapper.swift
// Corrected Version

import Foundation
import SwiftUI
import UIKit // Needed for UIImage
import FirebaseFirestore // Assuming you use these
import FirebaseFirestoreSwift // Assuming you use these
import RealityKit
import Combine

@available(visionOS 2.0, *) // Ensure this availability is correct for your target
class SpacesEntityWrapper: ObservableObject {
    static let shared = SpacesEntityWrapper()

    // Published properties - Already correctly optional!
    @Published private(set) var entity: Entity?
    @Published private(set) var spaceEntity: Entity?
    @Published private(set) var activeSceneEntity: Entity?

    @AppStorage("showEmojis") private var showEmojis = true // User preference
    @Published private(set) var isEmitting = false // State of the emitter

    // Task for auto-resetting the emitter
    private var resetTask: Task<Void, Never>?

    // Store original emitter properties for restoration
    private var originalImage: TextureResource?
    private var originalBirthRate: Float?
    private var originalSize: Float?
    private var haveOriginalProps = false

    private init() { // Private init for singleton
        print("🌐 SpacesEntityWrapper initialized")
    }

    // MARK: - Entity Management

    // This method already accepts Entity? - No change needed here
    func setEntity(_ newEntity: Entity?) {
        DispatchQueue.main.async { // Ensure main thread for @Published update
            if self.entity?.id != newEntity?.id { // Avoid redundant updates
                 self.entity = newEntity
                 print("🔄 Wrapper: Main entity set to \(newEntity?.name ?? "nil")")
                // Optional: If setting the general entity should trigger emitter prop capture:
                // Task { await self.captureOriginalEmitterProps() }
            }
        }
    }

    // --- CORRECTED: Accepts Entity? ---
    func setSpaceEntity(_ newEntity: Entity?) {
         DispatchQueue.main.async { // Ensure main thread
            if self.spaceEntity?.id != newEntity?.id {
                self.spaceEntity = newEntity
                print("🔄 Wrapper: Space entity set to \(newEntity?.name ?? "nil")")
                // Trigger property capture only if entity is not nil
                if newEntity != nil {
                    Task { await self.captureOriginalEmitterProps() }
                } else {
                    // Optional: Reset original props if space entity is cleared?
                    // self.resetOriginalEmitterProps()
                }
            }
        }
    }

    // --- CORRECTED: Accepts Entity? ---
    func setActiveSceneEntity(_ newEntity: Entity?) {
        DispatchQueue.main.async { // Ensure main thread
            if self.activeSceneEntity?.id != newEntity?.id {
                self.activeSceneEntity = newEntity
                print("🌟 Wrapper: Active scene entity set to \(newEntity?.name ?? "nil")")

                // --- CORRECTED: Handle potential nil ---
                if let entity = newEntity {
                    // Check scene connection only if entity exists
                     Task { @MainActor in // Still good practice to ensure main actor for scene checks
                        if entity.scene != nil {
                            print("✅ Active entity '\(entity.name)' is connected to scene")
                        } else if entity.parent != nil {
                            print("✅ Active entity '\(entity.name)' has a parent")
                        } else {
                            print("⚠️ Active entity '\(entity.name)' is not connected to scene or parent")
                        }
                        // Capture props only if entity is not nil
                        await self.captureOriginalEmitterProps()
                    }
                } else {
                    // Active entity is nil, no scene connection to check
                    print("ℹ️ Active scene entity is now nil.")
                     // Optional: Reset original props if active entity is cleared?
                     // self.resetOriginalEmitterProps()
                }
            }
        }
    }

    // Helper to potentially reset captured props if needed
    private func resetOriginalEmitterProps() {
        originalImage = nil
        originalBirthRate = nil
        originalSize = nil
        haveOriginalProps = false
        print("ℹ️ Reset captured original emitter properties.")
    }


    private func captureOriginalEmitterProps() async {
        // Only capture once unless explicitly reset
        if haveOriginalProps {
            // print("🔄 Already captured original emitter properties") // Reduce log noise
            return
        }

        // Use await MainActor.run to ensure UI thread access
        await MainActor.run {
            // Prioritize activeSceneEntity, then spaceEntity, then general entity
            let targetEntity = activeSceneEntity ?? spaceEntity ?? entity
            guard let targetEntity = targetEntity else {
                 // print("ℹ️ captureOriginalEmitterProps: No target entity available.") // Log if needed
                return
            }

            print("🔍 captureOriginalEmitterProps: Searching for 'VolumetericEmoji' in '\(targetEntity.name)'")
            if let emojiEntity = targetEntity.findEntity(named: "VolumetericEmoji"),
               var emitter = emojiEntity.components[ParticleEmitterComponent.self] { // Use var if you might modify it later, but let is safer if just reading
                originalImage = emitter.mainEmitter.image
                originalBirthRate = emitter.mainEmitter.birthRate
                originalSize = emitter.mainEmitter.size
                haveOriginalProps = true // Mark as captured

                print("✅ Captured original emitter properties from '\(emojiEntity.name)':")
                print("   - Has image: \(originalImage != nil ? "yes" : "no")")
                print("   - Birth rate: \(originalBirthRate?.description ?? "nil")")
                print("   - Size: \(originalSize?.description ?? "nil")")
            } else {
                 print("⚠️ captureOriginalEmitterProps: Could not find 'VolumetericEmoji' or its ParticleEmitterComponent in '\(targetEntity.name)'.")
            }
        }
    }

    // Getter remains the same
    func getSpaceEntity() -> Entity? {
        return spaceEntity
    }

    // Getter for active scene entity (useful for SpacesView)
    func getActiveSceneEntity() -> Entity? {
        return activeSceneEntity
    }

    // Getter for general entity (useful for SpacesView)
    func getEntity() -> Entity? {
        return entity
    }


    // removeEntity clears all - this is fine
    func removeEntity() async {
        print("🗑️ removeEntity called in Wrapper")
        await MainActor.run {
            // Remove from parent first if attached
            entity?.removeFromParent()
            spaceEntity?.removeFromParent() // Might be same as entity or activeSceneEntity
            activeSceneEntity?.removeFromParent() // Might be same as entity or spaceEntity

            // Clear references
            self.entity = nil
            self.spaceEntity = nil
            self.activeSceneEntity = nil

            // Reset emitter state too
            self.resetOriginalEmitterProps()
            self.isEmitting = false
            resetTask?.cancel()
            resetTask = nil
            print("✅ Entities removed and emitter state reset in Wrapper.")
        }
    }

    // MARK: - Cleanup

    func cleanup() async {
        print("🧹 Starting SpacesEntityWrapper cleanup")
        resetTask?.cancel() // Cancel any pending reset
        resetTask = nil
        await stopEmission() // Ensure emission is stopped
        await removeEntity() // Remove entities and clear refs
        print("✅ SpacesEntityWrapper cleanup completed")
    }

    // MARK: - Debug Helpers (No changes needed)

    func dumpEntityHierarchy(_ targetEntity: Entity?, level: Int = 0) {
        guard let currentEntity = targetEntity else {
            // print("Entity is nil at level \(level)") // Optional log
            return
        }

        let indent = String(repeating: "  ", count: level)
        print("\(indent)📦 \(currentEntity.name) (ID: \(currentEntity.id)) Enabled:\(currentEntity.isEnabled)")
        for component in currentEntity.components {
            // Provide more detail for common components
            var componentDesc = "\(type(of: component))"
            if let transform = component as? Transform {
                componentDesc += " Pos:\(transform.translation)"
            } else if let particles = component as? ParticleEmitterComponent {
                 componentDesc += " Emitting:\(particles.isEmitting) Image:\(particles.mainEmitter.image != nil)"
            }
            print("\(indent)  🔧 \(componentDesc)")
        }
        for child in currentEntity.children {
            dumpEntityHierarchy(child, level: level + 1)
        }
    }


    // MARK: - Emoji Management (Mostly unchanged, ensure nil checks)

    func setEmojiVisibility(_ isVisible: Bool) {
        print("👁️ Setting emoji visibility to: \(isVisible)")
        showEmojis = isVisible // Update AppStorage

        Task { @MainActor in // Ensure main actor for RealityKit updates
            let targetEntity = activeSceneEntity ?? spaceEntity ?? entity
            if let emojiEntity = findEmojiEntity(in: targetEntity) {
                emojiEntity.isEnabled = isVisible // Set visibility
                print("✅ Updated emoji visibility to \(isVisible) for entity: \(emojiEntity.name)")
                if !isVisible {
                    // If hiding, also stop any active emission immediately
                    await stopEmission()
                }
            } else {
                print("❌ Could not find VolumetericEmoji entity to update visibility")
            }
        }
    }

    func updateVolumetricEmojiTexture(with imageName: String) {
        guard showEmojis else {
            print("🚫 Emoji display is disabled via AppStorage, skipping emission for '\(imageName)'")
            return
        }

        print("🚀 Received request to emit emoji: \(imageName)")

        Task { @MainActor in // Ensure main actor context
            // Ensure original props are captured *before* potentially changing them
            // This might run multiple times if called quickly, but captureOriginalEmitterProps handles that.
            await captureOriginalEmitterProps()

            print("🎯 Starting emoji emission process for: \(imageName)")
            await proceedWithEmission(imageName: imageName)
        }
    }

    // MARK: - Entity Search (Unchanged)

    private func findEmojiEntity(in parent: Entity?) -> Entity? {
        guard let parent = parent else {
            // print("❌ Parent entity is nil when searching for emoji entity") // Optional log
            return nil
        }
        // Use RealityKit's built-in recursive search
        if let found = parent.findEntity(named: "VolumetericEmoji") {
            print("✅ Found emoji entity: \(found.name) in parent \(parent.name)")
            return found
        }
        // print("❌ Could not find 'VolumetericEmoji' entity within \(parent.name)") // Optional log
        return nil
    }

    // MARK: - Emission (Mostly unchanged, added logging, ensured MainActor)

    // MARK: - Emission

    // --- CORRECTED: Marked the entire function @MainActor ---
    @MainActor
    private func proceedWithEmission(imageName: String) async {
        // Now we are guaranteed to be on the MainActor here
        print("🔄 Starting emission process for image: \(imageName) on MainActor")
        resetTask?.cancel() // Cancel previous auto-reset if any

        let targetEntity = activeSceneEntity ?? spaceEntity ?? entity
        guard let targetEntity = targetEntity else {
            print("❌ proceedWithEmission: No target entity found (activeScene, space, or general). Cannot emit.")
            return
        }

        print("🔍 proceedWithEmission: Looking for 'VolumetericEmoji' in entity: \(targetEntity.name)")
        guard let emojiEntity = findEmojiEntity(in: targetEntity) else {
            print("❌ proceedWithEmission: Could not find 'VolumetericEmoji' entity in '\(targetEntity.name)'. Dumping hierarchy:")
            dumpEntityHierarchy(targetEntity) // Help debug if entity isn't found
            return
        }

        print("✅ proceedWithEmission: Found emoji entity: \(emojiEntity.name). IsEnabled: \(emojiEntity.isEnabled)")

        // Ensure the emoji entity itself is enabled before trying to emit
        if !emojiEntity.isEnabled {
             print("⚠️ proceedWithEmission: Emoji entity '\(emojiEntity.name)' is disabled. Enabling it.")
             emojiEntity.isEnabled = true // Attempt to enable it
        }

        guard let image = UIImage(named: imageName),
              let cgImage = image.cgImage else {
            print("❌ proceedWithEmission: Failed to load UIImage or CGImage for: \(imageName)")
            return
        }

        // Check if emitter component exists
         guard var emitter = emojiEntity.components[ParticleEmitterComponent.self] else {
                print("❌ proceedWithEmission: No ParticleEmitterComponent found on 'VolumetericEmoji' ('\(emojiEntity.name)'). Cannot emit.")
                return
            }

        // Load texture (can throw, needs try)
         do {
            // Texture loading is async, but its continuation will be on MainActor because the func is @MainActor
            let textureResource = try await TextureResource(image: cgImage, options: .init(semantic: .normal))

            // --- Modify Emitter (Guaranteed on MainActor) ---
            print("📊 Current emitter state before update - isEmitting: \(emitter.isEmitting), Image: \(emitter.mainEmitter.image != nil)")

            // Ensure original properties were captured if not already
            if !haveOriginalProps {
                print("⚠️ proceedWithEmission: Original props not captured yet. Capturing now.")
                originalImage = emitter.mainEmitter.image
                originalBirthRate = emitter.mainEmitter.birthRate
                originalSize = emitter.mainEmitter.size
                haveOriginalProps = true
                print("✅ Late-captured original emitter properties.")
            }

            // Apply new texture and settings
            emitter.mainEmitter.image = textureResource
            emitter.mainEmitter.size = 0.25 // Consider making this configurable
             // Make sure birth rate allows emission
            if emitter.mainEmitter.birthRate <= 0 {
                print("⚠️ proceedWithEmission: Emitter birth rate is \(emitter.mainEmitter.birthRate). Setting to original or 100 for emission.")
                emitter.mainEmitter.birthRate = originalBirthRate ?? 100 // Restore or use a default
            }
            emitter.isEmitting = true // Start emitting

            // IMPORTANT: Assign the modified component back to the entity
            emojiEntity.components[ParticleEmitterComponent.self] = emitter
             print("✅ Updated emitter component on '\(emojiEntity.name)' with image: \(imageName)")
             print("📊 Emitter state AFTER update - isEmitting: \(emitter.isEmitting), BirthRate: \(emitter.mainEmitter.birthRate), Size: \(emitter.mainEmitter.size), Image: \(emitter.mainEmitter.image != nil)")

            // Update published state
            self.isEmitting = true

             // --- Schedule Reset Task ---
             // Task still needs @MainActor because it runs *later*
             resetTask = Task { @MainActor [weak self] in // Capture self weakly
                 guard let self = self else { return } // Check weak self

                 do {
                     try await Task.sleep(for: .seconds(3)) // Wait 3 seconds

                     // Check if task was cancelled in the meantime
                     guard !Task.isCancelled else {
                         print("ℹ️ Emoji reset task cancelled.")
                         return
                     }

                     print("⏱️ Auto-resetting emoji image after 3 seconds...")
                     // Re-find the entity and component (already on MainActor)
                     let currentTargetEntity = self.activeSceneEntity ?? self.spaceEntity ?? self.entity
                     // --- LINE 278 AREA ---
                     guard let currentEmojiEntity = self.findEmojiEntity(in: currentTargetEntity),
                           var currentEmitter = currentEmojiEntity.components[ParticleEmitterComponent.self] else {
                         // This guard's else block and return are fine within an @MainActor Task closure
                         print("⚠️ Auto-reset: Could not find emoji entity or component anymore.")
                         self.isEmitting = false // Update state if entity/component is gone
                         return // Exit the Task
                     }

                     // Restore original properties if available
                     if self.haveOriginalProps {
                         print("🔄 Restoring original emitter properties...")
                         currentEmitter.mainEmitter.image = self.originalImage
                         if let size = self.originalSize { currentEmitter.mainEmitter.size = size }
                         if let birthRate = self.originalBirthRate { currentEmitter.mainEmitter.birthRate = birthRate }
                         currentEmitter.isEmitting = (self.originalBirthRate ?? 0) > 0
                         currentEmojiEntity.components[ParticleEmitterComponent.self] = currentEmitter
                         print("✅ Successfully restored original emitter state. IsEmitting: \(currentEmitter.isEmitting)")
                     } else {
                         // Fallback
                         print("⚠️ Auto-reset: No original props - setting image to nil and stopping emission.")
                         currentEmitter.mainEmitter.image = nil
                         currentEmitter.isEmitting = false
                         currentEmojiEntity.components[ParticleEmitterComponent.self] = currentEmitter
                     }
                     // Update published state based on final emitter state
                     self.isEmitting = currentEmitter.isEmitting

                 } catch is CancellationError {
                      print("ℹ️ Emoji reset task cancelled during sleep.")
                 } catch {
                     print("❌ Error during emoji reset task: \(error)")
                     self.isEmitting = false // Update state on error
                 }
             } // End of reset Task

        } catch {
             print("❌ proceedWithEmission: Failed to load TextureResource: \(error)")
             // Maybe set isEmitting false here too?
             // self.isEmitting = false
        }
    } // End of proceedWithEmission

    private func stopEmission() async {
        // Ensure execution on the main actor for RealityKit modifications
        await MainActor.run {
            print("🛑 Attempting to stop emission...")
            resetTask?.cancel() // Cancel any pending reset
            resetTask = nil

            let targetEntity = activeSceneEntity ?? spaceEntity ?? entity
            guard let targetEntity = targetEntity else {
                print("❌ stopEmission: No target entity found. Cannot stop.")
                return
            }

            print("🔍 stopEmission: Looking for emoji entity in '\(targetEntity.name)'")
            if let emojiEntity = findEmojiEntity(in: targetEntity) {
                if var particleEmitter = emojiEntity.components[ParticleEmitterComponent.self] { // Use var to modify
                    print("📊 Current emitter state before stopping - isEmitting: \(particleEmitter.isEmitting)")
                    if particleEmitter.isEmitting {
                        particleEmitter.isEmitting = false // Stop the emission
                        // IMPORTANT: Assign the modified component back
                        emojiEntity.components[ParticleEmitterComponent.self] = particleEmitter
                        print("✅ Emission explicitly stopped for \(emojiEntity.name).")
                    } else {
                         print("ℹ️ stopEmission: Emitter for \(emojiEntity.name) was already not emitting.")
                    }
                } else {
                    print("❓ stopEmission: Found emoji entity '\(emojiEntity.name)' but it has no ParticleEmitterComponent.")
                }
            } else {
                print("❌ stopEmission: Could not find 'VolumetericEmoji' entity in '\(targetEntity.name)' to stop emission.")
            }
            // Update published state regardless of whether component was found, as intent is to stop
            self.isEmitting = false
        }
    }


    // MARK: - Diagnostics (Unchanged - but ensure it uses MainActor for checks)

    func runDiagnostics() {
         print("--- 🔍 Running SpacesEntityWrapper Diagnostics ---")
         Task { @MainActor in // Run checks on MainActor
             let currentEntity = self.entity
             let currentSpaceEntity = self.spaceEntity
             let currentActiveSceneEntity = self.activeSceneEntity

             print("Entities:")
             print("  - General Entity: \(currentEntity?.name ?? "nil") (ID: \(currentEntity?.id.description ?? "N/A"))")
             print("  - Space Entity: \(currentSpaceEntity?.name ?? "nil") (ID: \(currentSpaceEntity?.id.description ?? "N/A"))")
             print("  - Active Scene Entity: \(currentActiveSceneEntity?.name ?? "nil") (ID: \(currentActiveSceneEntity?.id.description ?? "N/A"))")

             print("\nState:")
             print("  - isEmitting (Published): \(self.isEmitting)")
             print("  - showEmojis (AppStorage): \(self.showEmojis)")
             print("  - Have Original Emitter Props: \(self.haveOriginalProps)")
             if self.haveOriginalProps {
                  print("    - Original Image: \(self.originalImage != nil ? "Exists" : "nil")")
                  print("    - Original Birth Rate: \(self.originalBirthRate?.description ?? "nil")")
                  print("    - Original Size: \(self.originalSize?.description ?? "nil")")
             }
             print("  - Reset Task Active: \(self.resetTask != nil && !self.resetTask!.isCancelled)")

             print("\nActive Scene Entity Details:")
             if let sceneEntity = currentActiveSceneEntity {
                 if sceneEntity.scene != nil {
                     print("  - Connected to Scene: YES")
                 } else {
                      print("  - Connected to Scene: NO")
                      if sceneEntity.parent != nil {
                         print("    - Has Parent: YES (\(sceneEntity.parent!.name))")
                      } else {
                         print("    - Has Parent: NO")
                      }
                 }
                 print("  - Is Enabled: \(sceneEntity.isEnabled)")

                 print("\nEmoji Entity within Active Scene Entity:")
                 if let emojiEntity = sceneEntity.findEntity(named: "VolumetericEmoji") {
                     print("  - Found: YES (Name: \(emojiEntity.name), ID: \(emojiEntity.id))")
                     print("  - Is Enabled: \(emojiEntity.isEnabled)")

                     if let emitter = emojiEntity.components[ParticleEmitterComponent.self] {
                         print("  - ParticleEmitterComponent: YES")
                         print("    - isEmitting (Component): \(emitter.isEmitting)")
                         print("    - Has Image Texture: \(emitter.mainEmitter.image != nil)")
                         print("    - Birth Rate: \(emitter.mainEmitter.birthRate)")
                         print("    - Size: \(emitter.mainEmitter.size)")
                     } else {
                         print("  - ParticleEmitterComponent: NO")
                     }
                 } else {
                     print("  - Found: NO")
                     print("  - Hierarchy Dump of Active Scene Entity:")
                     dumpEntityHierarchy(sceneEntity)
                 }
             } else {
                  print("  - No Active Scene Entity set.")
             }
              print("--- Diagnostics Complete ---")
         }
    }


    deinit {
        print("♻️ SpacesEntityWrapper deinit")
        resetTask?.cancel() // Cancel task on deinit
        resetTask = nil
        // You generally shouldn't call async code directly from deinit.
        // If cleanup needs to happen, it should be triggered externally before
        // the wrapper is deallocated, or use Task.detached if absolutely necessary
        // (but be very careful with detached tasks).
        // Task { await cleanup() } // Avoid this pattern in deinit if possible.
    }
}
