//
//  WorldBuilderManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation
// MARK: - WorldBuilderManager.swift
import Foundation
import RealityKit
import Combine
import FirebaseFirestore
import FirebaseStorage

@MainActor
class WorldBuilderManager: ObservableObject {
    static let shared = WorldBuilderManager()
    
    // MARK: - Properties
    @Published var isVoiceActive = false
    @Published var currentWorld: WorldData?
    @Published var placedObjects: [PlacedObject] = []
    @Published var environment: EnvironmentPreset = .defaultOutdoor
    @Published var isGeneratingObject = false
    @Published var voiceTranscript = ""
    
    private var rootEntity: Entity?
    private var environmentEntity: Entity?
    private var objectsContainer: Entity?
    private var gridEntity: Entity?
    
    private let assetLoader = WorldAssetLoader()
    private let voiceController = VoiceController()
    private let meshyAPI = MeshyAPIClient()
    private var cancellables = Set<AnyCancellable>()
    
    // Grid and placement helpers
    private var placementGrid: PlacementGrid?
    private var ghostObject: Entity?
    
    // MARK: - Scene Setup
    func setupScene(in content: RealityViewContent) async {
        // Create root entity for the world
        let root = Entity()
        root.name = "WorldRoot"
        
        // Create containers
        let envContainer = Entity()
        envContainer.name = "Environment"
        
        let objContainer = Entity()
        objContainer.name = "Objects"
        
        // Setup placement grid (optional visual helper)
        let grid = await createPlacementGrid()
        grid.name = "PlacementGrid"
        grid.isEnabled = false // Hidden by default
        
        root.addChild(envContainer)
        root.addChild(objContainer)
        root.addChild(grid)
        
        content.add(root)
        
        self.rootEntity = root
        self.environmentEntity = envContainer
        self.objectsContainer = objContainer
        self.gridEntity = grid
        
        // Load default environment
        await loadEnvironment(.defaultOutdoor)
    }
    
    func updateScene(in content: RealityViewContent) {
        // Handle scene updates based on state changes
    }
    
    // MARK: - Environment Management
    func loadEnvironment(_ preset: EnvironmentPreset) async {
        guard let envContainer = environmentEntity else { return }
        
        // Clear existing environment
        envContainer.children.removeAll()
        
        // Load skybox
        if let skyboxEntity = await createSkybox(for: preset) {
            envContainer.addChild(skyboxEntity)
        }
        
        // Setup lighting
        setupLighting(for: preset, in: envContainer)
        
        // Add ground plane
        let ground = await createGroundPlane(for: preset)
        envContainer.addChild(ground)
        
        self.environment = preset
    }
    
    private func createSkybox(for preset: EnvironmentPreset) async -> Entity? {
        // Create skybox based on preset
        let skybox = Entity()
        
        switch preset {
        case .forest:
            // Load forest HDR environment
            do {
                let texture = try await TextureResource(named: "forest_skybox")
                skybox.components[ImageBasedLightComponent.self] = ImageBasedLightComponent(source: .single(texture))
            } catch {
                print("Failed to load skybox: \(error)")
            }
        case .desert:
            // Load desert environment
            break
        case .snow:
            // Load snowy environment
            break
        case .indoor:
            // Load indoor environment
            break
        default:
            // Default outdoor environment
            break
        }
        
        return skybox
    }
    
    private func setupLighting(for preset: EnvironmentPreset, in container: Entity) {
        // Configure lighting based on environment
        let lightEntity = Entity()
        
        var lightComponent = DirectionalLightComponent()
        lightComponent.intensity = preset.lightIntensity
        lightComponent.color = .init(preset.lightColor)
        
        lightEntity.components[DirectionalLightComponent.self] = lightComponent
        
        // Position the light
        lightEntity.position = [0, 10, 5]
        lightEntity.look(at: .zero, from: lightEntity.position, relativeTo: nil)
        
        container.addChild(lightEntity)
    }
    
    private func createGroundPlane(for preset: EnvironmentPreset) async -> Entity {
        let ground = Entity()
        
        // Create a large ground plane
        let mesh = MeshResource.generatePlane(width: 100, depth: 100)
        
        var material = SimpleMaterial()
        material.color = .init(tint: preset.groundColor)
        material.roughness = 0.8
        
        ground.components[ModelComponent.self] = ModelComponent(mesh: mesh, materials: [material])
        
        // Add collision for placement
        let shape = ShapeResource.generateBox(width: 100, height: 0.1, depth: 100)
        ground.components[CollisionComponent.self] = CollisionComponent(shapes: [shape])
        
        ground.position.y = -0.05
        
        return ground
    }
    
    // MARK: - Object Placement
    func placeObject(type: String, at position: SIMD3<Float>, with properties: ObjectProperties? = nil) async {
        guard let container = objectsContainer else { return }
        
        // Load or generate the object
        let objectEntity = await loadObject(type: type, properties: properties)
        
        // Position the object
        objectEntity.position = position
        
        // Add to scene
        container.addChild(objectEntity)
        
        // Track placed object
        let placedObject = PlacedObject(
            id: UUID().uuidString,
            type: type,
            position: position,
            rotation: .zero,
            scale: .one,
            properties: properties
        )
        
        placedObjects.append(placedObject)
        
        // Save to Firebase
        await saveObjectToFirebase(placedObject)
    }
    
    private func loadObject(type: String, properties: ObjectProperties?) async -> Entity {
        // Check if it's a preset object or needs generation
        if let presetEntity = await assetLoader.loadPresetAsset(type: type) {
            return presetEntity
        }
        
        // Generate with Meshy if needed
        if let properties = properties, properties.needsGeneration {
            return await generateObjectWithMeshy(description: properties.description ?? type)
        }
        
        // Fallback to primitive
        return createPrimitive(type: type)
    }
    
    private func createPrimitive(type: String) -> Entity {
        let entity = Entity()
        
        let mesh: MeshResource
        switch type.lowercased() {
        case "cube", "box":
            mesh = MeshResource.generateBox(size: 1.0)
        case "sphere", "ball":
            mesh = MeshResource.generateSphere(radius: 0.5)
        case "cylinder":
            mesh = MeshResource.generateCylinder(height: 1.0, radius: 0.5)
        default:
            mesh = MeshResource.generateBox(size: 1.0)
        }
        
        let material = SimpleMaterial(color: .gray, roughness: 0.5, isMetallic: false)
        entity.components[ModelComponent.self] = ModelComponent(mesh: mesh, materials: [material])
        
        // Add physics
        entity.components[CollisionComponent.self] = CollisionComponent(shapes: [.generateConvex(from: mesh)])
        entity.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(massProperties: .default, material: .default)
        
        return entity
    }
    
    // MARK: - Meshy Integration
    private func generateObjectWithMeshy(description: String) async -> Entity {
        isGeneratingObject = true
        
        do {
            let modelURL = await meshyAPI.generateModel(from: description)
            let entity = await assetLoader.loadFromURL(modelURL)
            isGeneratingObject = false
            return entity
        } catch {
            print("Meshy generation failed: \(error)")
            isGeneratingObject = false
            // Return placeholder
            return createPrimitive(type: "cube")
        }
    }
    
    // MARK: - Voice Interface
    func connectVoiceInterface() async {
        await voiceController.initialize()
        
        voiceController.onTranscript = { [weak self] transcript in
            self?.voiceTranscript = transcript
        }
        
        voiceController.onCommand = { [weak self] command in
            await self?.handleVoiceCommand(command)
        }
        
        await voiceController.startListening()
        isVoiceActive = true
    }
    
    private func handleVoiceCommand(_ command: VoiceCommand) async {
        switch command.action {
        case .addObject:
            let position = command.position ?? getDefaultPlacementPosition()
            await placeObject(type: command.objectType, at: position, with: command.properties)
            
        case .modifyEnvironment:
            if let envType = command.environmentType {
                await loadEnvironment(envType)
            }
            
        case .deleteObject:
            if let targetId = command.targetId {
                removeObject(withId: targetId)
            }
            
        case .generateCustom:
            if let description = command.customDescription {
                let position = command.position ?? getDefaultPlacementPosition()
                let entity = await generateObjectWithMeshy(description: description)
                objectsContainer?.addChild(entity)
                entity.position = position
            }
            
        default:
            break
        }
    }
    
    // MARK: - Interaction Handlers
    func handleTap(on entity: Entity, at location: SIMD3<Float>) {
        // Handle object selection or placement
        if let ghost = ghostObject {
            // Place the ghost object
            ghost.position = location
            confirmPlacement()
        } else {
            // Select the tapped object
            selectObject(entity)
        }
    }
    
    func handleDrag(entity: Entity, translation: SIMD3<Float>) {
        // Move the selected object
        entity.position += translation
        
        // Update the placed object data
        if let index = placedObjects.firstIndex(where: { $0.id == entity.name }) {
            placedObjects[index].position = entity.position
        }
    }
    
    // MARK: - Helper Methods
    private func getDefaultPlacementPosition() -> SIMD3<Float> {
        // Return position in front of user
        return [0, 0, -2]
    }
    
    private func createPlacementGrid() async -> Entity {
        let grid = Entity()
        
        // Create grid mesh
        let gridSize: Float = 20
        let gridSpacing: Float = 1
        
        // Add grid lines (simplified)
        for i in -10...10 {
            let lineX = Entity()
            let meshX = MeshResource.generateBox(width: gridSize, height: 0.01, depth: 0.01)
            lineX.components[ModelComponent.self] = ModelComponent(mesh: meshX, materials: [SimpleMaterial(color: .white.withAlphaComponent(0.3))])
            lineX.position = [0, 0, Float(i) * gridSpacing]
            grid.addChild(lineX)
            
            let lineZ = Entity()
            let meshZ = MeshResource.generateBox(width: 0.01, height: 0.01, depth: gridSize)
            lineZ.components[ModelComponent.self] = ModelComponent(mesh: meshZ, materials: [SimpleMaterial(color: .white.withAlphaComponent(0.3))])
            lineZ.position = [Float(i) * gridSpacing, 0, 0]
            grid.addChild(lineZ)
        }
        
        return grid
    }
    
    private func selectObject(_ entity: Entity) {
        // Visual feedback for selection
        // Add outline or highlight
    }
    
    private func confirmPlacement() {
        guard let ghost = ghostObject else { return }
        
        ghost.components[OpacityComponent.self] = nil
        ghostObject = nil
        
        // Save the placement
        let placedObject = PlacedObject(
            id: UUID().uuidString,
            type: ghost.name,
            position: ghost.position,
            rotation: ghost.orientation,
            scale: ghost.scale
        )
        
        placedObjects.append(placedObject)
    }
    
    private func removeObject(withId id: String) {
        placedObjects.removeAll { $0.id == id }
        
        // Remove from scene
        if let entity = objectsContainer?.children.first(where: { $0.name == id }) {
            entity.removeFromParent()
        }
    }
    
    // MARK: - Firebase Integration
    private func saveObjectToFirebase(_ object: PlacedObject) async {
        // Save to Firestore
        let db = Firestore.firestore()
        
        do {
            try await db.collection("worlds")
                .document(currentWorld?.id ?? "default")
                .collection("objects")
                .document(object.id)
                .setData(object.dictionary)
        } catch {
            print("Failed to save object: \(error)")
        }
    }
    
    // MARK: - Cleanup
    func cleanup() async {
        await voiceController.stopListening()
        isVoiceActive = false
        
        rootEntity?.removeFromParent()
        rootEntity = nil
        
        placedObjects.removeAll()
        currentWorld = nil
    }
    
    func initialize() async {
        // Initialize world builder
        print("🎨 World Builder initialized")
    }
}
