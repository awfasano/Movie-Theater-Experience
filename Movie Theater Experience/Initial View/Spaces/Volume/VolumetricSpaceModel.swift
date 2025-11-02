//
//  VolumetricSpaceModel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/2/25.
//

import Foundation
import RealityKit
import Combine
import SwiftUI

// MARK: - ViewModel
/// View model for the VolumetricSpaceView
class VolumetricSpaceViewModel: ObservableObject {
    // Published properties
    @Published var entity: Entity?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var autoRotate = true
    
    // Services
    private let service = SpaceService.shared
    private let entityWrapper = SpacesEntityWrapper.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Loading
    
    /// Load a space and its associated 3D content
    func loadSpace(_ space: SpaceData) {
        print("🔄 Loading space: \(space.spaceName)")
        
        isLoading = true
        error = nil
        entity = nil
        
        service.loadSpace(from: space)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                self.isLoading = false
                
                if case .failure(let error) = completion {
                    print("❌ Failed to load space: \(error)")
                    self.error = error
                }
            }, receiveValue: { [weak self] loadedEntity in
                guard let self = self else { return }
                print("✅ Space loaded successfully: \(space.spaceName)")
                
                // Process entity for preview
                let processedEntity = self.processEntityForPreview(loadedEntity, space: space)
                self.entity = processedEntity
                
                // Store in entity wrapper for immersive view access
                self.entityWrapper.setEntity(loadedEntity.clone(recursive: true))
                self.entityWrapper.setSpaceEntity(loadedEntity.clone(recursive: true))
                
                // Debug
                print("📊 Entity hierarchy in view model:")
                self.entityWrapper.dumpEntityHierarchy(loadedEntity)
            })
            .store(in: &cancellables)
    }
    
    /// Process entity for preview display
    private func processEntityForPreview(_ originalEntity: Entity, space: SpaceData) -> Entity {
        // Create a container entity
        let containerEntity = Entity()
        
        // Clone the entity
        let entity = originalEntity.clone(recursive: true)
        
        // If there's a specific intro entity, use it
        if let introName = space.introEntityName, !introName.isEmpty,
           let introEntity = findEntityByName(introName, in: entity) {
            print("✅ Using intro entity: \(introName)")
            
            // Clone and center the intro entity
            let clonedIntro = introEntity.clone(recursive: true)
            centerEntityAtOrigin(clonedIntro)
            containerEntity.addChild(clonedIntro)
        } else {
            // Otherwise use the whole entity
            print("ℹ️ No intro entity found, using full model")
            centerEntityAtOrigin(entity)
            containerEntity.addChild(entity)
        }
        
        // Ensure all entities are enabled
        enableAllEntities(containerEntity)
        
        return containerEntity
    }
    
    @MainActor
    func canEnterSpace() -> Bool {
        // Access the singleton directly using .shared
        guard !AppModel.current.username.isEmpty else {
            print("❌ [ViewModel] Entry check FAILED: Username is not set.")
            return false
        }
        
        print("✅ [ViewModel] Entry check PASSED.")
        return true
    }
    
    /// Center an entity at the origin
    private func centerEntityAtOrigin(_ entity: Entity) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let center = SIMD3<Float>(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )
        entity.position = -center
    }
    
    /// Find an entity by name in the hierarchy
    private func findEntityByName(_ name: String, in entity: Entity) -> Entity? {
        if entity.name == name {
            return entity
        }
        
        for child in entity.children {
            if let found = findEntityByName(name, in: child) {
                return found
            }
        }
        
        return nil
    }
    
    /// Enable all entities in the hierarchy
    private func enableAllEntities(_ entity: Entity) {
        entity.isEnabled = true
        for child in entity.children {
            enableAllEntities(child)
        }
    }
    
    /// Clean up resources
    func cleanup() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}
