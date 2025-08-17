//
//  WorldBuilderManager.swift
//  Movie Theater Experience
//
//  Fixed version with proper Firebase integration and scene management
//

import Foundation
import RealityKit
import Combine
import FirebaseFirestore
import FirebaseStorage
import UIKit

@MainActor
class WorldBuilderManager: ObservableObject {
    static let shared = WorldBuilderManager()
    
    // MARK: - Published Properties
    @Published var isVoiceActive = false
    @Published var currentWorld: WorldData?
    @Published var placedObjects: [PlacedObject] = []
    @Published var environment: EnvironmentPreset = .defaultOutdoor
    @Published var isGeneratingObject = false
    @Published var voiceTranscript = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Scene Entities
    private var rootEntity: Entity?
    private var environmentEntity: Entity?
    private var objectsContainer: Entity?
    private var gridEntity: Entity?
    private var lightingEntity: Entity?
    
    // MARK: - Services
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let assetLoader = WorldAssetLoader()
    private let voiceController = VoiceController()
    private let meshyAPI = MeshyAPIClient()
    private var cancellables = Set<AnyCancellableable>()
    
    // MARK: - Object Tracking
    private var objectEntities: [String: Entity] = [:] // Maps object ID to entity
    private var selectedObjectId: String?
    
    private init() {
        setupFirebaseListeners()
    }
    
    // MARK: - Scene Management
    func setupScene(in content: RealityViewContent) async {
        print("🎨 Setting up World Builder scene")
        
        // Clear any existing content
        content.entities.removeAll()
        
        // Create hierarchy
        let root = Entity()
        root.name = "WorldBuilderRoot"
        
        let envContainer = Entity()
        envContainer.name = "Environment"
        
        let objContainer = Entity()
        objContainer.name = "ObjectsContainer"
        
        let lightContainer = Entity()
        lightContainer.name = "LightingContainer"
        
        let gridContainer = Entity()
        gridContainer.name = "PlacementGrid"
        gridContainer.isEnabled = false
        
        // Build hierarchy
        root.addChild(envContainer)
        root.addChild(objContainer)
        root.addChild(lightContainer)
        root.addChild(gridContainer)
        
        content.add(root)
        
        // Store references
        self.rootEntity = root
        self.environmentEntity = envContainer
        self.objectsContainer = objContainer
        self.lightingEntity = lightContainer
        self.gridEntity = gridContainer
        
        // Load default environment
        await loadEnvironment(.defaultOutdoor)
        
        // Load current world if available
        if let worldId = getCurrentWorldId() {
            await loadWorld(worldId: worldId)
        } else {
            await createNewWorld()
        }
    }
    
    func updateScene(in content: RealityViewContent) {
        // Handle any real-time updates
        // This is called when @Published properties change
    }
    
    // MARK: - World Management
    func createNewWorld() async {
        isLoading = true
        errorMessage = nil
        
        let newWorld = WorldData(
            id: UUID().uuidString,
            name: "New World \(Date().formatted(date: .abbreviated, time: .shortened))",
            createdAt: Date(),
            environment: environment,
            objects: []
        )
        
        do {
            // Save to Firebase
            try await db.collection("worlds").document(newWorld.id).setData([
                "name": newWorld.name,
                "createdAt": newWorld.createdAt,
                "environment": newWorld.environment.rawValue,
                "objects": []
            ])
            
            // Update local state
            currentWorld = newWorld
            placedObjects = []
            UserDefaults.standard.set(newWorld.id, forKey: "currentWorldId")
            
            print("✅ Created new world: \(newWorld.name)")
            
        } catch {
            errorMessage = "Failed to create world: \(error.localizedDescription)"
            print("❌ Failed to create world: \(error)")
        }
        
        isLoading = false
    }
    
    func loadWorld(worldId: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Load world metadata
            let worldDoc = try await db.collection("worlds").document(worldId).getDocument()
            
            guard let worldData = worldDoc.data() else {
                throw NSError(domain: "WorldBuilder", code: 404, userInfo: [NSLocalizedDescriptionKey: "World not found"])
            }
            
            // Parse world data
            let world = WorldData(
                id: worldId,
                name: worldData["name"] as? String ?? "Unnamed World",
                createdAt: (worldData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                environment: EnvironmentPreset(rawValue: worldData["environment"] as? String ?? "outdoor") ?? .defaultOutdoor,
                objects: []
            )
            
            // Load objects
            let objectsSnapshot = try await db.collection("worlds").document(worldId).collection("objects").getDocuments()
            
            var objects: [PlacedObject] = []
            for doc in objectsSnapshot.documents {
                if let object = parseObjectFromFirebase(doc.data(), id: doc.documentID) {
                    objects.append(object)
                }
            }
            
            // Update state
            currentWorld = world
            placedObjects = objects
            environment = world.environment
            
            // Load environment
            await loadEnvironment(world.environment)
            
            // Place objects in scene
            await placeAllObjects()
            
            UserDefaults.standard.set(worldId, forKey: "currentWorldId")
            print("✅ Loaded world: \(world.name) with \(objects.count) objects")
            
        } catch {
            errorMessage = "Failed to load world: \(error.localizedDescription)"
            print("❌ Failed to load world: \(error)")
        }
        
        isLoading = false
    }
    
    func saveWorld() async {
        guard let world = currentWorld else { return }
        
        isLoading = true
        
        do {
            // Update world metadata
            try await db.collection("worlds").document(world.id).updateData([
                "name": world.name,
                "environment": environment.rawValue,
                "updatedAt": Date()
            ])
            
            // Save all objects
            for object in placedObjects {
                try await saveObjectToFirebase(object)
            }
            
            print("✅ Saved world: \(world.name)")
            
        } catch {
            errorMessage = "Failed to save world: \(error.localizedDescription)"
            print("❌ Failed to save world: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Environment Management
    func loadEnvironment(_ preset: EnvironmentPreset) async {
        guard let envContainer = environmentEntity,
              let lightContainer = lightingEntity else { return }
        
        print("🌍 Loading environment: \(preset.rawValue)")
        
        // Clear existing environment
        envContainer.children.removeAll()
        lightContainer.children.removeAll()
        
        // Load skybox based on preset
        await loadSkybox(for: preset, in: envContainer)
        
        // Setup lighting
        setupLighting(for: preset, in: lightContainer)
        
        // Add ground plane
        let ground = await createGroundPlane(for: preset)
        envContainer.addChild(ground)
        
        // Update state
        self.environment = preset
        
        // Save environment change if we have a current world
        if let world = currentWorld {
            Task {
                try? await db.collection("worlds").document(world.id).updateData([
                    "environment": preset.rawValue
                ])
            }
        }
    }
    
    private func loadSkybox(for preset: EnvironmentPreset, in container: Entity) async {
        do {
            let skyboxName = getSkyboxAssetName(for: preset)
            
            // Try to load from RealityKitContent first
            if let skyboxTexture = try? await TextureResource(named: skyboxName) {
                let skyboxEntity = Entity()
                skyboxEntity.components[ImageBasedLightComponent.self] = ImageBasedLightComponent(
                    source: .single(skyboxTexture),
                    intensityExponent: preset.lightIntensity / 1000.0
                )
                container.addChild(skyboxEntity)
                print("✅ Loaded skybox: \(skyboxName)")
            } else {
                // Fallback to procedural skybox
                await createProceduralSkybox(for: preset, in: container)
            }
            
        } catch {
            print("⚠️ Failed to load skybox, using procedural: \(error)")
            await createProceduralSkybox(for: preset, in: container)
        }
    }
    
    private func getSkyboxAssetName(for preset: EnvironmentPreset) -> String {
        switch preset {
        case .defaultOutdoor: return "DefaultSkybox"
        case .forest: return "ForestSkybox"
        case .desert: return "DesertSkybox"
        case .snow: return "SnowSkybox"
        case .indoor: return "IndoorSkybox"
        case .space: return "SpaceSkybox"
        }
    }
    
    private func createProceduralSkybox(for preset: EnvironmentPreset, in container: Entity) async {
        // Create a large sphere with appropriate texture/color for the environment
        let skyboxEntity = Entity()
        let mesh = MeshResource.generateSphere(radius: 50)
        
        var material = SimpleMaterial()
        material.color = .init(tint: preset.lightColor)
        material.isMetallic = false
        material.roughness = 1.0
        
        skyboxEntity.components[ModelComponent.self] = ModelComponent(mesh: mesh, materials: [material])
        skyboxEntity.scale = SIMD3<Float>(-1, 1, -1) // Invert to face inward
        
        container.addChild(skyboxEntity)
        print("✅ Created procedural skybox for \(preset.rawValue)")
    }
    
    private func setupLighting(for preset: EnvironmentPreset, in container: Entity) {
        // Main directional light
        let mainLight = Entity()
        var directionalLight = DirectionalLightComponent()
        directionalLight.intensity = preset.lightIntensity
        directionalLight.color = .init(preset.lightColor)
        directionalLight.isRealWorldProxy = false
        
        mainLight.components[DirectionalLightComponent.self] = directionalLight
        mainLight.position = [0, 10, 5]
        mainLight.look(at: .zero, from: mainLight.position, relativeTo: nil)
        
        container.addChild(mainLight)
        
        // Ambient light for softer shadows
        let ambientLight = Entity()
        var ambientComponent = DirectionalLightComponent()
        ambientComponent.intensity = preset.lightIntensity * 0.3
        ambientComponent.color = .init(preset.lightColor)
        
        ambientLight.components[DirectionalLightComponent.self] = ambientComponent
        ambientLight.position = [0, 10, -5]
        ambientLight.look(at: .zero, from: ambientLight.position, relativeTo: nil)
        
        container.addChild(ambientLight)
    }
    
    private func createGroundPlane(for preset: EnvironmentPreset) async -> Entity {
        let ground = Entity()
        ground.name = "GroundPlane"
        
        // Create mesh
        let mesh = MeshResource.generatePlane(width: 100, depth: 100)
        
        // Create material based on environment
        var material = SimpleMaterial()
        material.color = .init(tint: preset.groundColor)
        material.roughness = 0.8
        material.isMetallic = false
        
        ground.components[ModelComponent.self] = ModelComponent(mesh: mesh, materials: [material])
        
        // Add collision for ray casting
        let shape = ShapeResource.generateBox(width: 100, height: 0.1, depth: 100)
        ground.components[CollisionComponent.self] = CollisionComponent(shapes: [shape])
        
        ground.position.y = -0.05
        
        return ground
    }
    
    // MARK: - Object Management
    func placeObject(type: String, at position: SIMD3<Float>, with properties: ObjectProperties? = nil) async {
        guard let container = objectsContainer else { return }
        
        print("🎯 Placing object: \(type) at \(position)")
        
        // Create object entity
        let objectEntity = await createObjectEntity(type: type, properties: properties)
        objectEntity.position = position
        
        // Generate unique ID
        let objectId = UUID().uuidString
        objectEntity.name = objectId
        
        // Add to scene
        container.addChild(objectEntity)
        
        // Track in dictionaries
        objectEntities[objectId] = objectEntity
        
        // Create placed object data
        let placedObject = PlacedObject(
            id: objectId,
            type: type,
            position: position,
            rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            scale: SIMD3<Float>(1, 1, 1),
            properties: properties
        )
        
        // Update arrays
        placedObjects.append(placedObject)
        
        // Save to Firebase
        await saveObjectToFirebase(placedObject)
        
        print("✅ Placed object: \(type) with ID: \(objectId)")
    }
    
    private func placeAllObjects() async {
        guard let container = objectsContainer else { return }
        
        // Clear existing objects
        container.children.removeAll()
        objectEntities.removeAll()
        
        // Place each object
        for object in placedObjects {
            let entity = await createObjectEntity(type: object.type, properties: object.properties)
            entity.name = object.id
            entity.position = object.position
            entity.orientation = object.rotation
            entity.scale = object.scale
            
            container.addChild(entity)
            objectEntities[object.id] = entity
        }
        
        print("✅ Placed \(placedObjects.count) objects in scene")
    }
    
    private func createObjectEntity(type: String, properties: ObjectProperties?) async -> Entity {
        // Try to load preset asset first
        if let presetEntity = await assetLoader.loadPresetAsset(type: type) {
            return presetEntity
        }
        
        // Fall back to primitive
        return createPrimitiveEntity(type: type, properties: properties)
    }
    
    private func createPrimitiveEntity(type: String, properties: ObjectProperties?) -> Entity {
        let entity = Entity()
        entity.name = "Primitive_\(type)"
        
        let mesh: MeshResource
        switch type.lowercased() {
        case "cube", "box":
            mesh = MeshResource.generateBox(size: 1.0)
        case "sphere", "ball":
            mesh = MeshResource.generateSphere(radius: 0.5)
        case "cylinder":
            mesh = MeshResource.generateCylinder(height: 1.0, radius: 0.5)
        case "plane":
            mesh = MeshResource.generatePlane(width: 1.0, depth: 1.0)
        default:
            mesh = MeshResource.generateBox(size: 1.0)
        }
        
        // Create material
        var material = SimpleMaterial()
        if let colorString = properties?.color,
           let color = UIColor(hexString: colorString) {
            material.color = .init(tint: color)
        } else {
            material.color = .init(tint: .systemBlue)
        }
        material.roughness = 0.6
        material.isMetallic = false
        
        entity.components[ModelComponent.self] = ModelComponent(mesh: mesh, materials: [material])
        
        // Add physics
        let shape = ShapeResource.generateConvex(from: mesh)
        entity.components[CollisionComponent.self] = CollisionComponent(shapes: [shape])
        entity.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
            massProperties: .default,
            material: .default,
            mode: .dynamic
        )
        
        // Add input handling
        entity.components[InputTargetComponent.self] = InputTargetComponent()
        
        return entity
    }
    
    func removeObject(withId objectId: String) async {
        // Remove from scene
        if let entity = objectEntities[objectId] {
            entity.removeFromParent()
            objectEntities.removeValue(forKey: objectId)
        }
        
        // Remove from arrays
        placedObjects.removeAll { $0.id == objectId }
        
        // Remove from Firebase
        if let worldId = currentWorld?.id {
            try? await db.collection("worlds").document(worldId).collection("objects").document(objectId).delete()
        }
        
        print("🗑️ Removed object: \(objectId)")
    }
    
    // MARK: - Interaction Handlers
    func handleTap(on entity: Entity, at location: SIMD3<Float>) {
        if let objectId = entity.name, objectEntities[objectId] != nil {
            // Select object
            selectedObjectId = objectId
            print("👆 Selected object: \(objectId)")
            
            // Add visual feedback
            addSelectionFeedback(to: entity)
        } else {
            // Deselect
            clearSelection()
        }
    }
    
    func handleDrag(entity: Entity, translation: SIMD3<Float>) {
        guard let objectId = entity.name,
              let index = placedObjects.firstIndex(where: { $0.id == objectId }) else { return }
        
        // Update entity position
        entity.position += translation
        
        // Update data model
        placedObjects[index].position = entity.position
        
        print("🔄 Moved object \(objectId) to \(entity.position)")
    }
    
    func handleDragEnd(entity: Entity) {
        guard let objectId = entity.name,
              let object = placedObjects.first(where: { $0.id == objectId }) else { return }
        
        // Save position to Firebase
        Task {
            await saveObjectToFirebase(object)
        }
    }
    
    private func addSelectionFeedback(to entity: Entity) {
        // Remove existing selection feedback
        clearSelection()
        
        // Add outline or highlight
        // This could be a wireframe, glow effect, or outline
        let outlineEntity = Entity()
        // Implementation depends on your visual feedback preference
        entity.addChild(outlineEntity)
    }
    
    private func clearSelection() {
        selectedObjectId = nil
        // Remove selection feedback from all objects
        for entity in objectEntities.values {
            entity.children.removeAll { $0.name.contains("selection") }
        }
    }
    
    // MARK: - Firebase Helpers
    private func getCurrentWorldId() -> String? {
        return UserDefaults.standard.string(forKey: "currentWorldId")
    }
    
    private func parseObjectFromFirebase(_ data: [String: Any], id: String) -> PlacedObject? {
        guard let type = data["type"] as? String,
              let positionArray = data["position"] as? [Float],
              positionArray.count >= 3 else { return nil }
        
        let position = SIMD3<Float>(positionArray[0], positionArray[1], positionArray[2])
        
        var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        if let rotationArray = data["rotation"] as? [Float], rotationArray.count >= 4 {
            rotation = simd_quatf(ix: rotationArray[1], iy: rotationArray[2], iz: rotationArray[3], r: rotationArray[0])
        }
        
        var scale = SIMD3<Float>(1, 1, 1)
        if let scaleArray = data["scale"] as? [Float], scaleArray.count >= 3 {
            scale = SIMD3<Float>(scaleArray[0], scaleArray[1], scaleArray[2])
        }
        
        let properties = ObjectProperties(
            color: data["color"] as? String,
            material: data["material"] as? String,
            description: data["description"] as? String,
            needsGeneration: data["needsGeneration"] as? Bool ?? false
        )
        
        return PlacedObject(
            id: id,
            type: type,
            position: position,
            rotation: rotation,
            scale: scale,
            properties: properties
        )
    }
    
    private func saveObjectToFirebase(_ object: PlacedObject) async {
        guard let worldId = currentWorld?.id else { return }
        
        let data: [String: Any] = [
            "type": object.type,
            "position": [object.position.x, object.position.y, object.position.z],
            "rotation": [object.rotation.real, object.rotation.imag.x, object.rotation.imag.y, object.rotation.imag.z],
            "scale": [object.scale.x, object.scale.y, object.scale.z],
            "color": object.properties?.color ?? "",
            "material": object.properties?.material ?? "",
            "description": object.properties?.description ?? "",
            "needsGeneration": object.properties?.needsGeneration ?? false,
            "updatedAt": Date()
        ]
        
        do {
            try await db.collection("worlds").document(worldId).collection("objects").document(object.id).setData(data)
        } catch {
            print("❌ Failed to save object: \(error)")
        }
    }
    
    private func setupFirebaseListeners() {
        // Listen for world changes in real-time
        // Implementation depends on whether you want collaborative editing
    }
    
    // MARK: - Voice Interface
    func connectVoiceInterface() async {
        guard !isVoiceActive else { return }
        
        await voiceController.initialize()
        
        voiceController.onTranscript = { [weak self] transcript in
            Task { @MainActor in
                self?.voiceTranscript = transcript
            }
        }
        
        voiceController.onCommand = { [weak self] command in
            await self?.handleVoiceCommand(command)
        }
        
        await voiceController.startListening()
        isVoiceActive = true
        
        print("🎤 Voice interface connected")
    }
    
    func disconnectVoiceInterface() async {
        await voiceController.stopListening()
        isVoiceActive = false
        voiceTranscript = ""
        print("🔇 Voice interface disconnected")
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
                await removeObject(withId: targetId)
            } else if let selectedId = selectedObjectId {
                await removeObject(withId: selectedId)
            }
            
        case .moveObject:
            if let targetId = command.targetId ?? selectedObjectId,
               let entity = objectEntities[targetId],
               let newPosition = command.position {
                entity.position = newPosition
                if let index = placedObjects.firstIndex(where: { $0.id == targetId }) {
                    placedObjects[index].position = newPosition
                    await saveObjectToFirebase(placedObjects[index])
                }
            }
            
        case .generateCustom:
            if let description = command.customDescription {
                let position = command.position ?? getDefaultPlacementPosition()
                let properties = ObjectProperties(description: description, needsGeneration: true)
                await placeObject(type: "custom", at: position, with: properties)
            }
        }
    }
    
    // MARK: - Utility
    private func getDefaultPlacementPosition() -> SIMD3<Float> {
        // Position in front of user (assuming user is at origin facing -Z)
        return SIMD3<Float>(0, 0, -2)
    }
    
    // MARK: - Cleanup
    func cleanup() async {
        print("🧹 Cleaning up World Builder")
        
        await disconnectVoiceInterface()
        
        // Clear scene references
        rootEntity?.removeFromParent()
        rootEntity = nil
        environmentEntity = nil
        objectsContainer = nil
        lightingEntity = nil
        gridEntity = nil
        
        // Clear tracking
        objectEntities.removeAll()
        selectedObjectId = nil
        
        // Clear state
        placedObjects.removeAll()
        currentWorld = nil
        errorMessage = nil
        
        cancellables.removeAll()
    }
}

// MARK: - Extensions
extension UIColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}
