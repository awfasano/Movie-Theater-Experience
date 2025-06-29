import Foundation
import SwiftUI
import _RealityKit_SwiftUI
import Combine

// Add this extension to help with entity discovery
extension Entity {
    func getAllNamedEntities() -> [(name: String, entity: Entity)] {
        var result: [(name: String, entity: Entity)] = []
        
        func traverse(_ entity: Entity) {
            if !entity.name.isEmpty {
                result.append((name: entity.name, entity: entity))
            }
            for child in entity.children {
                traverse(child)
            }
        }
        
        traverse(self)
        return result
    }
}

struct VolumetricSpaceWrapper: View {
    let space: SpaceData
    @State private var entity: Entity?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var rotationAngle: Angle = .zero
    @State private var currentUserCount: Int
    @State private var maxUserCount: Int
    @State private var showJoinFailedAlert = false
    @State private var scale: Float

    // State to manage the entity's position offset interactively.
    @State private var positionOffset: SIMD3<Float> = .zero
    
    // State to hold the pointer entity.
    @State private var indicatorEntity: ModelEntity?
    
    // State for the target's name, position, and found status.
    @State private var targetEntityName: String
    @State private var targetPosition: SIMD3<Float> = .zero
    @State private var wasTargetFound: Bool = false
    
    // New states for entity discovery
    @State private var availableEntities: [String] = []
    @State private var showEntityPicker = false
    @State private var selectedEntityForCentering: String = ""
    @State private var showDebugBounds = true
    @State private var debugBoundsEntity: Entity?
    @State private var isFastMovement = false
    @State private var particleEmittersActive = true
    
    // Environment
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    // Services and Timers
    private let spaceService = SpaceService.shared
    let rotationTimer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    
    init(space: SpaceData) {
        self.space = space
        self._currentUserCount = State(initialValue: space.currentUserCount)
        self._maxUserCount = State(initialValue: space.maxUserCount)
        self._scale = State(initialValue: Float(space.volumeInitialScale ?? 0.2))
        
        let initialOffset = SIMD3<Float>(
            Float(space.volumeOffsetX ?? 0.0),
            Float(space.volumeOffsetY ?? 0.0),
            Float(space.volumeOffsetZ ?? 0.0)
        )
        self._positionOffset = State(initialValue: initialOffset)
        
        self._targetEntityName = State(initialValue: space.initialTargetEntityForVolume ?? "")
    }
    
    private let moveIncrement: Float = 0.01
    private let fastMoveIncrement: Float = 0.1

    var body: some View {
        ZStack {
            if let entity = entity {
                ZStack {
                    // The 3D model view
                    RealityView { content in
                        content.add(entity)
                        
                        entity.scale = SIMD3<Float>(repeating: scale)
                        entity.position = positionOffset
                        
                    } update: { content in
                        guard let sceneEntity = content.entities.first else { return }
                        
                        sceneEntity.scale = SIMD3<Float>(repeating: scale)
                        sceneEntity.orientation = simd_quatf(angle: Float(rotationAngle.radians), axis: [0, 1, 0])
                        sceneEntity.position = positionOffset
                        
                        // Update debug bounds if enabled
                        if showDebugBounds {
                            updateDebugBounds(for: sceneEntity)
                        } else {
                            debugBoundsEntity?.removeFromParent()
                            debugBoundsEntity = nil
                        }
                        
                        guard let indicator = findEntityRecursively(named: "direction_indicator", in: sceneEntity), !targetEntityName.isEmpty else { return }
                        
                        let found: Bool
                        let localPosition: SIMD3<Float>
                        var worldPositionForIndicator: SIMD3<Float> = .zero

                        if let targetEntity = findEntityRecursively(named: targetEntityName, in: sceneEntity) {
                            localPosition = targetEntity.position(relativeTo: sceneEntity)
                            worldPositionForIndicator = targetEntity.position(relativeTo: nil)
                            found = true
                        } else {
                            localPosition = .zero
                            worldPositionForIndicator = sceneEntity.position(relativeTo: nil)
                            found = false
                        }

                        if self.targetPosition != localPosition || self.wasTargetFound != found {
                            DispatchQueue.main.async {
                                self.targetPosition = localPosition
                                self.wasTargetFound = found
                            }
                        }
                        
                        let indicatorPosition = indicator.position(relativeTo: nil)
                        indicator.look(at: worldPositionForIndicator, from: indicatorPosition, relativeTo: nil)
                    }
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let delta = Float(value.magnification - 1.0)
                                scale = max(0.01, scale + delta * 0.1)
                            }
                    )
                    .onReceive(rotationTimer) { _ in
                        rotationAngle += Angle(degrees: 0.1)
                        if rotationAngle >= Angle(degrees: 360) {
                            rotationAngle = .zero
                        }
                    }
                }
                
                // --- UI Controls Overlay ---
                VStack {
                    // Top row with entity finder button
                    HStack {
                        HStack(spacing: 4) {
                            Circle().fill(occupancyColor).frame(width: 8, height: 8)
                            Text("\(currentUserCount)/\(maxUserCount) users").font(.callout).foregroundColor(.white)
                        }
                        .padding(8).background(.ultraThinMaterial).cornerRadius(8)
                        
                        Spacer()
                        
                        // Entity Finder Button
                        Button(action: { showEntityPicker.toggle() }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Find Entity")
                            }
                            .foregroundColor(.white).padding(8).background(.ultraThinMaterial).cornerRadius(8)
                        }
                        
                        Button(action: { showDebugBounds.toggle() }) {
                            Image(systemName: showDebugBounds ? "eye.slash" : "eye")
                                .foregroundColor(.white).padding(8).background(.ultraThinMaterial).cornerRadius(8)
                        }
                        
                        Button(action: { toggleParticleEmitters() }) {
                            Image(systemName: particleEmittersActive ? "sparkles.slash" : "sparkles")
                                .foregroundColor(.white).padding(8).background(.ultraThinMaterial).cornerRadius(8)
                        }
                        
                        Button(action: { resetView() }) {
                            Text("Reset View").foregroundColor(.white).padding(8).background(.ultraThinMaterial).cornerRadius(8)
                        }
                    }
                    
                    // Entity picker list
                    if showEntityPicker && !availableEntities.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Select Entity to Center:").font(.headline).padding(.bottom, 5)
                            ScrollView {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(availableEntities, id: \.self) { entityName in
                                        Button(action: {
                                            centerOnEntity(named: entityName)
                                            showEntityPicker = false
                                        }) {
                                            HStack {
                                                Text(entityName)
                                                    .foregroundColor(entityName == targetEntityName ? .yellow : .white)
                                                Spacer()
                                                if entityName == targetEntityName {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.yellow)
                                                }
                                            }
                                            .padding(8)
                                            .background(Color.gray.opacity(0.3))
                                            .cornerRadius(5)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .frame(maxWidth: 300)
                    }
                    
                    Spacer()
                    
                    // Combined controls with enhanced movement
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(String(format: "Scale: %.2f", scale))
                            Text(String(format: "Volume Offset: [%.2f, %.2f, %.2f]", positionOffset.x, positionOffset.y, positionOffset.z))
                            
                            if !targetEntityName.isEmpty {
                                Text("Target: \(targetEntityName)")
                                    .foregroundColor(wasTargetFound ? .yellow : .orange)
                                Text(String(format: "Target Local Pos: [%.2f, %.2f, %.2f]", targetPosition.x, targetPosition.y, targetPosition.z))
                                    .foregroundColor(wasTargetFound ? .yellow : .orange)
                                
                                if wasTargetFound {
                                    // Show the world position where the target will appear after offset
                                    let worldPosAfterOffset = targetPosition + positionOffset
                                    Text(String(format: "Target World Pos: [%.2f, %.2f, %.2f]", worldPosAfterOffset.x, worldPosAfterOffset.y, worldPosAfterOffset.z))
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                } else {
                                    Text("(Entity not found, showing origin)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            HStack {
                                Toggle("Fast Movement", isOn: $isFastMovement)
                                    .toggleStyle(.button)
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .glassBackgroundEffect(in: .rect(cornerRadius: 10))
                        
                        // Enhanced movement controls
                        VStack {
                            Text("Movement Controls").font(.caption)
                            HStack(spacing: 10) {
                                VStack {
                                    Text("X").font(.caption)
                                    Button { moveEntity(axis: .x, positive: true) } label: { Image(systemName: "arrow.right") }
                                    Button { moveEntity(axis: .x, positive: false) } label: { Image(systemName: "arrow.left") }
                                }
                                VStack {
                                    Text("Y").font(.caption)
                                    Button { moveEntity(axis: .y, positive: true) } label: { Image(systemName: "arrow.up") }
                                    Button { moveEntity(axis: .y, positive: false) } label: { Image(systemName: "arrow.down") }
                                }
                                VStack {
                                    Text("Z").font(.caption)
                                    Button { moveEntity(axis: .z, positive: false) } label: { Image(systemName: "arrow.forward") }
                                    Button { moveEntity(axis: .z, positive: true) } label: { Image(systemName: "arrow.backward") }
                                }
                            }
                            
                            // Quick positioning buttons
                            VStack(spacing: 5) {
                                if !targetEntityName.isEmpty {
                                    Button(action: { centerOnEntity(named: targetEntityName) }) {
                                        Text("Center on Target")
                                            .font(.caption)
                                            .padding(5)
                                            .background(Color.yellow.opacity(0.3))
                                            .cornerRadius(5)
                                    }
                                }
                                
                                Button(action: { centerVolumeAtOrigin() }) {
                                    Text("Center Volume")
                                        .font(.caption)
                                        .padding(5)
                                        .background(Color.blue.opacity(0.3))
                                        .cornerRadius(5)
                                }
                            }
                        }
                        .buttonStyle(.bordered).padding().glassBackgroundEffect(in: .rect(cornerRadius: 10))
                    }
                    
                    // Enter Space button
                    Button(action: { enterImmersiveSpace() }) {
                        HStack {
                            Image(systemName: "globe")
                            Text("Enter Space")
                        }
                        .font(.headline).foregroundColor(.white).padding().frame(width: 200)
                        .background(LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(12).shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(.plain).padding(.bottom, 20)
                    
                    // Scale controls
                    HStack {
                        Button(action: { scale = max(0.01, scale - 0.05) }) { Image(systemName: "minus.circle.fill") }
                        Slider(value: Binding(get: { Double(scale) }, set: { scale = Float($0) }), in: 0.01...2.0).frame(width: 150)
                        Button(action: { scale = min(2.0, scale + 0.05) }) { Image(systemName: "plus.circle.fill") }
                    }
                    .font(.system(size: 32)).padding(16).background(.ultraThinMaterial).cornerRadius(15)
                }
                .padding()

            } else if isLoading {
                VStack {
                    ProgressView().scaleEffect(1.5).padding()
                    Text("Loading volumetric content...").font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadError != nil {
                errorView
            }
        }
        .onAppear {
            loadEntity()
            setupUserCountListener()
        }
        .onDisappear {
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
        }
        .alert("Could Not Join Space", isPresented: $showJoinFailedAlert) {
            Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please go to the Settings app and set a username before joining a shared space.")
        }
    }
    
    // New helper functions
    private func moveEntity(axis: Axis, positive: Bool) {
        let increment = isFastMovement ? fastMoveIncrement : moveIncrement
        let direction: Float = positive ? 1 : -1
        
        switch axis {
        case .x:
            positionOffset.x += increment * direction
        case .y:
            positionOffset.y += increment * direction
        case .z:
            positionOffset.z += increment * direction
        }
    }
    
    private func centerOnEntity(named entityName: String) {
        guard let rootEntity = entity,
              let targetEntity = findEntityRecursively(named: entityName, in: rootEntity) else {
            print("❌ Could not find entity named: \(entityName)")
            return
        }
        
        // Update the target entity name
        targetEntityName = entityName
        
        // Get the target's position in the root entity's coordinate space
        let targetPositionInScene = targetEntity.position(relativeTo: rootEntity)
        
        // To center the target, we need to move the entire volume so the target appears at origin
        // This means offsetting by the negative of the target's position
        let newOffset = -targetPositionInScene
        
        print("🎯 Centering on '\(entityName)':")
        print("   Target local position: \(targetPositionInScene)")
        print("   Setting volume offset to: \(newOffset)")
        
        // Animate to the new position
        withAnimation(.easeInOut(duration: 0.5)) {
            positionOffset = newOffset
        }
    }
    
    private func toggleParticleEmitters() {
        guard let rootEntity = entity else { return }
        
        particleEmittersActive.toggle()
        
        let emitterCount = updateParticleEmitters(in: rootEntity, isActive: particleEmittersActive)
        
        print("🎆 Particle emitters \(particleEmittersActive ? "enabled" : "disabled")")
        print("   Found and updated \(emitterCount) particle emitter(s)")
    }
    
    private func updateParticleEmitters(in entity: Entity, isActive: Bool) -> Int {
        var count = 0
        
        // Check if this entity has a ParticleEmitterComponent
        if var emitter = entity.components[ParticleEmitterComponent.self] {
            // Toggle the isEmitting property
            emitter.isEmitting = isActive
            
            // Update the component
            entity.components[ParticleEmitterComponent.self] = emitter
            count += 1
            
            print("   - Updated emitter on entity: '\(entity.name.isEmpty ? "unnamed" : entity.name)' - isEmitting: \(isActive)")
        }
        
        // Recursively check all children
        for child in entity.children {
            count += updateParticleEmitters(in: child, isActive: isActive)
        }
        
        return count
    }
    
    private func centerVolumeAtOrigin() {
        withAnimation(.easeInOut(duration: 0.5)) {
            positionOffset = .zero
        }
        print("🎯 Centered volume at origin")
    }
    
    private func updateDebugBounds(for entity: Entity) {
        debugBoundsEntity?.removeFromParent()
        
        let bounds = entity.visualBounds(relativeTo: nil)
        let boxMesh = MeshResource.generateBox(width: bounds.extents.x,
                                                height: bounds.extents.y,
                                                depth: bounds.extents.z)
        
        var material = SimpleMaterial()
        material.color = .init(tint: .yellow.withAlphaComponent(0.3))
        material.metallic = 0
        material.roughness = 1
        
        let boxEntity = ModelEntity(mesh: boxMesh, materials: [material])
        boxEntity.position = bounds.center
        
        debugBoundsEntity = boxEntity
        entity.parent?.addChild(boxEntity)
    }
    
    private enum Axis {
        case x, y, z
    }
    
    private var occupancyColor: Color {
        let percentage = Float(currentUserCount) / Float(max(1, maxUserCount))
        switch percentage {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }
    
    private func setupUserCountListener() {
        guard let spaceId = space.id else { return }
        spaceService.getSpaceUpdates(for: spaceId)
            .receive(on: RunLoop.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    print("Error in user count listener: \(error)")
                }
            } receiveValue: { updatedSpace in
                self.currentUserCount = updatedSpace.currentUserCount
                self.maxUserCount = updatedSpace.maxUserCount
            }
            .store(in: &cancellables)
    }
    
    private func resetView() {
        scale = Float(space.volumeInitialScale ?? 0.2)
        rotationAngle = .zero
        positionOffset = SIMD3<Float>(
            Float(space.volumeOffsetX ?? 0.0),
            Float(space.volumeOffsetY ?? 0.0),
            Float(space.volumeOffsetZ ?? 0.0)
        )
    }
    
    private func enterImmersiveSpace() {
        guard !appModel.username.isEmpty else {
            showJoinFailedAlert = true
            return
        }
        appModel.selectedSpace = space
        Task { await openImmersiveSpace(id: appModel.spacesID) }
    }
    
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 50)).foregroundColor(.red)
            Text("Unable to Load Space").font(.title2).fontWeight(.semibold)
            Text("We couldn't load this content right now. Please try again later.").font(.body).multilineTextAlignment(.center).padding(.horizontal).foregroundColor(.secondary)
            Button("Try Again") { loadEntity() }.buttonStyle(.borderedProminent).padding(.top, 10)
        }
        .padding(30).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(radius: 5)
    }
    
    private func loadEntity() {
        isLoading = true
        loadError = nil
        entity = nil
        
        spaceService.loadSpace(from: space) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let loadedEntity):
                    let rootEntity = Entity()
                    let modelContainer = Entity()
                    
                    let contentSource = findEntityRecursively(named: space.introEntityName ?? "", in: loadedEntity) ?? loadedEntity
                    let contentClone = contentSource.clone(recursive: true)
                    
                    let bounds = contentClone.visualBounds(relativeTo: nil)
                    contentClone.position = -bounds.center
                    modelContainer.addChild(contentClone)
                    rootEntity.addChild(modelContainer)
                    
                    // Discover all named entities
                    let namedEntities = rootEntity.getAllNamedEntities()
                    self.availableEntities = namedEntities.map { $0.name }.sorted()
                    
                    print("🔍 Found \(availableEntities.count) named entities: \(availableEntities)")
                    
                    // Check for particle emitters
                    let emitterCount = countParticleEmitters(in: rootEntity)
                    if emitterCount > 0 {
                        print("🎆 Found \(emitterCount) particle emitter(s) in the scene")
                    }
                    
                    if let targetNameToCenter = space.initialTargetEntityForVolume, !targetNameToCenter.isEmpty {
                        if let entityToCenterOn = findEntityRecursively(named: targetNameToCenter, in: rootEntity) {
                            let targetPositionInScene = entityToCenterOn.position(relativeTo: rootEntity)
                            self.positionOffset = -targetPositionInScene
                        }
                    }
                    
                    let indicator = createIndicator()
                    self.indicatorEntity = indicator
                    rootEntity.addChild(indicator)
                    
                    self.entity = rootEntity
                    self.isLoading = false
                    
                case .failure(let error):
                    self.isLoading = false
                    self.loadError = error
                    print("⚠️ Entity loading error: \(error)")
                }
            }
        }
    }

    private func createIndicator() -> ModelEntity {
        let mesh = MeshResource.generateCone(height: 0.005, radius: 0.005)
        let material = SimpleMaterial(color: .yellow, isMetallic: false)
        let indicator = ModelEntity(mesh: mesh, materials: [material])
        
        indicator.name = "direction_indicator"
        indicator.position = [0, 0.0, 0]
        
        return indicator
    }

    private func countParticleEmitters(in entity: Entity) -> Int {
        var count = 0
        
        if entity.components[ParticleEmitterComponent.self] != nil {
            count += 1
        }
        
        for child in entity.children {
            count += countParticleEmitters(in: child)
        }
        
        return count
    }
    
    private func findEntityRecursively(named name: String, in entity: Entity) -> Entity? {
        if entity.name == name {
            return entity
        }
        for child in entity.children {
            if let found = findEntityRecursively(named: name, in: child) {
                return found
            }
        }
        return nil
    }
}
