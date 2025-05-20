import SwiftUI
import RealityKit
import RealityKitContent
import Combine

struct SpacesView: View {
    // MARK: - Properties
    @ObservedObject var spaceService = SpaceService.shared
    @ObservedObject var entityWrapper = SpacesEntityWrapper.shared
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.realityKitScene) private var realityKitScene
    //@EnvironmentObject var audioLoader: SpatialAudioLoader
    
    // State
    @State private var selectedSpace: SpaceData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastSpaceID: Entity.ID? = nil   // memo


    
    // Anchor for placing content in the scene
    @State private var anchorEntity = AnchorEntity()
    
    // Notification State
    @State private var notificationSentForEntityID: Entity.ID? = nil
    @State private var notificationPostTask: Task<Void, Never>? = nil
    
    // Root entity reference
    @State private var rootEntity: Entity? = nil
    
    // Volume control visibility
    @State private var showVolumeControl = false
    
    // Combine subscriptions
    @State private var cancellables = Set<AnyCancellable>()
    
    
    private let audioLoader: SpatialAudioLoader

    /// Designated init; `audioLoader` is required.
    init(audioLoader: SpatialAudioLoader) {
        self.audioLoader = audioLoader
    }
    
    // MARK: - Body
    var body: some View {
        // Split the body into smaller view components
        ZStack {
            // Main RealityView component
            mainRealityView
            
            // Loading and error overlays
            overlayViews
            
            // Volume control overlay
            if showVolumeControl, let space = selectedSpace {
                VolumeControlView(
                    audioLoader: audioLoader,
                    spaceEntity: entityWrapper.getSpaceEntity() ?? anchorEntity,
                    spaceMeta: space
                )
                .padding(.bottom, 40)
            }
            
            // Volume control toggle button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showVolumeControl.toggle()
                    }) {
                        Image(systemName: showVolumeControl ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.title)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 30)
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            print("📱 SpacesView appeared")
            initializeSpace()
        }
        .onChange(of: entityWrapper.getSpaceEntity()?.id) { oldId, newId in
            handleEntityIdChangeForNotification(oldId: oldId, newId: newId)
        }
        .onChange(of: appModel.selectedSpace?.currentSeat) { oldSeat, newSeat in
            handleSeatChange(oldSeat: oldSeat, newSeat: newSeat)
        }
        .onDisappear {
            cleanupView()
        }
    }
    
    // MARK: - View Components
    private var mainRealityView: some View {
        RealityView { content in
            content.add(anchorEntity)
        } update: { _ in
            // lightweight – runs every frame
            if let e = entityWrapper.getSpaceEntity(),
               e.id != lastSpaceID                       // NEW space?
            {
                Task { @MainActor in
                    ensureEntityIsParented(e)            // run on main actor, outside the frame
                }
            }
        }
        .ignoresSafeArea()
    }

    
    private var overlayViews: some View {
        Group {
            if isLoading && notificationSentForEntityID == nil {
                ProgressView("Loading space...")
                    .padding()
                    .background(.thinMaterial, in: .rect(cornerRadius: 10))
            } else if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
                    .background(.thinMaterial, in: .rect(cornerRadius: 10))
            }
        }
    }
    
    // MARK: - Core Functionality
    
    // Missing method that was causing the compilation error
    private func handleEntityIdChangeForNotification(oldId: Entity.ID?, newId: Entity.ID?) {
        notificationPostTask?.cancel()
        notificationPostTask = nil
        
        // Update UI to reflect changes
        
        guard let currentNewId = newId, oldId != currentNewId else {
            Task { @MainActor in self.notificationSentForEntityID = nil }
            return
        }
        
        // Schedule notification task
        Task { @MainActor in
            self.notificationSentForEntityID = nil
            
            self.notificationPostTask = Task {
                await postNotification(for: currentNewId)
            }
        }
    }
    
    private func initializeSpace() {
        // Reset notification state
        notificationSentForEntityID = nil
        notificationPostTask?.cancel()
        
        // Reset view state
        isLoading = false
        errorMessage = nil
        rootEntity = nil
        
        // Stop any existing audio
        audioLoader.stopAllAudio()

        // --- Join Space ---
        // Join the space as soon as the view is initialized
        if let spaceId = appModel.selectedSpace?.id {
            Task {
                let success = await spaceService.joinSpace(spaceId)
                if success {
                    print("✅ Successfully joined space: \(spaceId)")
                } else {
                    print("⚠️ Failed to join space: \(spaceId)")
                }
            }
        }
        // --- End Join Space ---

        // Ensure the current seat is always set to "seat_1" for a new space
        if let currentSpace = appModel.selectedSpace {
            if currentSpace.currentSeat == nil || currentSpace.currentSeat!.isEmpty {
                appModel.updateSelectedSpaceSeat(to: "seat_1")
            }
        }

        if let currentSpace = appModel.selectedSpace,
           let entity       = entityWrapper.getSpaceEntity(),
           entity.name == currentSpace.spaceName {

            selectedSpace = currentSpace
            openWindowsIfNeeded()

            // 🚀
            Task { @MainActor in
                ensureEntityIsParented(entity)
                applyViewerOffset(for: entity)
                await audioLoader.loadAudioForSpace(rootEntity: entity)
            }
            
            return // important: skip the call to loadSpace()
        }
        
        else {
            loadSpace()
        }
    }
    
    private func loadSpace() {
        resetViewState()
        
        let spaceToLoad = appModel.selectedSpace ?? spaceService.spaces.first
        self.selectedSpace = spaceToLoad
        
        if let space = spaceToLoad {
            // Load selected space
            loadSpaceEntity(for: space)
        } else {
            // Fetch spaces from service
            fetchSpacesAndLoadFirst()
        }
    }
    
    private func resetViewState() {
        notificationSentForEntityID = nil
        isLoading = true
        errorMessage = nil
        notificationPostTask?.cancel()
        rootEntity = nil
        
        // Stop all audio
        audioLoader.stopAllAudio()

        entityWrapper.setSpaceEntity(nil)
        entityWrapper.setActiveSceneEntity(nil)
        anchorEntity.children.removeAll()
        openWindowsIfNeeded()
    }
    
    private func fetchSpacesAndLoadFirst() {
        spaceService.fetchSpaces()
        spaceService.$spaces
            .dropFirst()
            .first(where: { !$0.isEmpty })
            .sink { fetchedSpaces in
                guard let firstSpace = fetchedSpaces.first else {
                    Task { @MainActor in
                        self.handleLoadError("Failed to load space data (empty list).")
                    }
                    return
                }
                
                if self.selectedSpace == nil {
                    self.selectedSpace = firstSpace
                    self.loadSpaceEntity(for: firstSpace)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Adds `entity` to `anchorEntity` if it isn’t there yet.
    @MainActor
    private func ensureEntityIsParented(_ entity: Entity) {
        let hasEntity = anchorEntity.children.contains(where: { $0.id == entity.id })
        guard !hasEntity else { return }              // ← nothing to do

        anchorEntity.children.removeAll()             // remove *other* models, not this one
        anchorEntity.addChild(entity)
    }

    
    private func debugPrintAllTransforms(of entity: Entity, level: Int = 0) {
        let indent = String(repeating: "  ", count: level)
        let q = entity.orientation.vector
        print("\(indent)\(entity.name): orientation = \(q), position = \(entity.position)")
        for child in entity.children {
            debugPrintAllTransforms(of: child, level: level+1)
        }
    }
    
    private func loadSpaceEntity(for space: SpaceData) {
        isLoading = true
        
        spaceService.loadSpace(from: space) { result in
            Task { @MainActor in
                // Skip stale loads
                guard space.id == self.selectedSpace?.id else {
                    if self.entityWrapper.getSpaceEntity() == nil { self.isLoading = false }
                    return
                }
                
                switch result {
                case .success(let loadedEntity):
                    self.isLoading = false

                    let entity = loadedEntity.clone(recursive: true)
                    entity.name     = space.spaceName
                    entity.isEnabled = true
                    /* …all the existing work… */

                    self.entityWrapper.setEntity(entity)
                    self.entityWrapper.setSpaceEntity(entity)
                    self.entityWrapper.setActiveSceneEntity(entity)

                    // 🚀 <-- add this block
                    Task { @MainActor in
                        ensureEntityIsParented(entity)          // anchor it
                        applyViewerOffset(for: entity)          // center it for the viewer
                        await audioLoader.loadAudioForSpace(    // start the speakers
                            rootEntity: entity)
                    }

                    
                    // Load spatial audio for the space
                    
                case .failure(let error):
                    self.handleLoadError("Failed to load \(space.spaceName): \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func findRootEntity(in entity: Entity) -> Entity? {
        // First check for direct child named "Root"
        if let root = entity.children.first(where: { $0.name == "Root" }) {
            return root
        }
        
        // Then try deep search for "Root"
        if let root = findEntityDeep(named: "Root", in: entity) {
            return root
        }
        
        // Last try lowercase "root"
        return findEntityDeep(named: "root", in: entity)
    }
    
    private func configureInitialPosition(entity: Entity, space: SpaceData) {
        guard let seats = space.seats, !seats.isEmpty else { return }
        
        // Don't set position here, will be handled in updateEntityInAnchor.
        // Just make sure a seat is selected.
        // Default to seat_1 if no seat is selected.
        if space.currentSeat == nil || space.currentSeat!.isEmpty {
            appModel.updateSelectedSpaceSeat(to: "seat_1")
        }
    }
    
    private func updateEntityInAnchor(_ e: Entity) {
        ensureEntityIsParented(e)
        applyViewerOffset(for: e)          // see (3)
    }
    
    @MainActor
    private func applyViewerOffset(for spaceEntity: Entity) {
        guard
          let space = getSpaceForScene(for: spaceEntity.id),
          let root  = findRootEntity(in: spaceEntity)
        else { return }

        root.position = SIMD3(
            Float(space.viewerXAdjustment),
            Float(space.viewerYAdjustment),
            Float(space.viewerZAdjustment)
        )
    }


    
    private func handleSeatChange(oldSeat: String?, newSeat: String?) {
        guard
            let spaceEntity = entityWrapper.getSpaceEntity(),
            let space = getSpaceForScene(for: spaceEntity.id),
            let seatID = newSeat,
            let seatEntity = findEntityDeep(named: seatID, in: spaceEntity),
            let oldSeatEntity = findEntityDeep(named: oldSeat ?? "seat_1", in: spaceEntity)

        else {
            return
        }

        // 1) seat position including your root-offset
        let seatLocalPos = seatEntity.position(relativeTo: spaceEntity)
        let oldSeatLocalPos = oldSeatEntity.position(relativeTo: spaceEntity)

        // 2) recompute your viewer offset
        let viewerOffset = SIMD3<Float>(
            Float(space.viewerXAdjustment),
            Float(space.viewerYAdjustment),
            Float(space.viewerZAdjustment)
        )

        // 3) desired anchor = viewerOffset - seatLocalPos
        let newAnchorPos =  anchorEntity.position+oldSeatLocalPos-seatLocalPos

        print("🪑 Moving to seat \(seatID): seatLocalPos=\(seatLocalPos), newAnchorPos=\(newAnchorPos)")

        // 4) apply absolutely, not additively
        withAnimation(.easeInOut(duration: 2)) {
            anchorEntity.position = newAnchorPos
        }
    }
    
    @MainActor
    private func postNotification(for entityId: Entity.ID) async {
        // Wait to ensure scene is stable.
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
            return // Task interrupted.
        }
        
        guard !Task.isCancelled,
              let scene = realityKitScene else {
            return
        }
        
        // Post notification with appropriate target.
        if let root = rootEntity, isEntityInScene(root) {
            NotificationCenter.default.post(
                name: NSNotification.Name("RealityKit.NotificationTrigger"),
                object: nil,
                userInfo: [
                    "RealityKit.NotificationTrigger.Scene": scene,
                    "RealityKit.NotificationTrigger.Entity": root,
                    "RealityKit.NotificationTrigger.Identifier": "loop"
                ]
            )
        } else if let entity = entityWrapper.getSpaceEntity() {
            if let foundRoot = findRootEntity(in: entity), isEntityInScene(foundRoot) {
                self.rootEntity = foundRoot
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("RealityKit.NotificationTrigger"),
                    object: nil,
                    userInfo: [
                        "RealityKit.NotificationTrigger.Scene": scene,
                        "RealityKit.NotificationTrigger.Entity": foundRoot,
                        "RealityKit.NotificationTrigger.Identifier": "loop"
                    ]
                )
            } else {
                NotificationCenter.default.post(
                    name: NSNotification.Name("RealityKit.NotificationTrigger"),
                    object: nil,
                    userInfo: [
                        "RealityKit.NotificationTrigger.Scene": scene,
                        "RealityKit.NotificationTrigger.Identifier": "loop"
                    ]
                )
            }
        } else {
            NotificationCenter.default.post(
                name: NSNotification.Name("RealityKit.NotificationTrigger"),
                object: nil,
                userInfo: [
                    "RealityKit.NotificationTrigger.Scene": scene,
                    "RealityKit.NotificationTrigger.Identifier": "loop"
                ]
            )
        }
        
        self.notificationSentForEntityID = entityId
    }
    
    @MainActor
    private func handleLoadError(_ message: String) {
        self.isLoading = false
        self.errorMessage = message
        
        if entityWrapper.getSpaceEntity()?.name == selectedSpace?.spaceName {
            entityWrapper.setSpaceEntity(nil)
            entityWrapper.setActiveSceneEntity(nil)
        }
        
        // Stop all audio playback on error
        audioLoader.stopAllAudio()

        self.notificationSentForEntityID = nil
        self.notificationPostTask?.cancel()
        self.notificationPostTask = nil
        self.rootEntity = nil
    }
    
    private func cleanupView() {
        // --- Leave Space ---
        // Leave the space before cleaning up the view state
        if let spaceId = selectedSpace?.id {
            Task {
                await spaceService.leaveSpace(spaceId)
                print("✅ Successfully left space: \(spaceId)")
            }
        }
        // --- End Leave Space ---
        
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        notificationPostTask?.cancel()
        notificationPostTask = nil
        
        // Stop all audio playback
        audioLoader.stopAllAudio()

        Task {
            await entityWrapper.cleanup()
        }
        
        notificationSentForEntityID = nil
        selectedSpace = nil
        rootEntity = nil
        anchorEntity.children.removeAll()
    }
    
    // MARK: - Helper Methods
    private func getSpaceForScene(for entityID: Entity.ID) -> SpaceData? {
        if let currentSpace = selectedSpace, entityWrapper.getSpaceEntity()?.id == entityID {
            return currentSpace
        }
        if let appModelSpace = appModel.selectedSpace, entityWrapper.getSpaceEntity()?.name == appModelSpace.spaceName {
            return appModelSpace
        }
        if let currentSpace = selectedSpace, currentSpace.spaceName == entityWrapper.getSpaceEntity()?.name {
            return currentSpace
        }
        return nil
    }
    
    private func findEntityDeep(named name: String, in parent: Entity) -> Entity? {
        if parent.name == name { return parent }
        for child in parent.children {
            if let found = findEntityDeep(named: name, in: child) {
                return found
            }
        }
        return nil
    }
    
    private func isEntityInScene(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let currentEntity = current {
            if currentEntity.scene != nil {
                return true
            }
            current = currentEntity.parent
        }
        return false
    }
    
    private func enableAllEntities(in entity: Entity) {
        entity.isEnabled = true
        for child in entity.children {
            enableAllEntities(in: child)
        }
    }
    
    private func openWindowsIfNeeded() {
        openWindow(id: "spaceNavBar")
        openWindow(id: "spaceMap")
    }
    
    // MARK: - Sphere Markers
    /// Adds large sphere markers at seat_1 and seat_2 positions.
    private func addSphereMarkers(to spaceEntity: Entity) {
        print("🔍 Starting to add sphere markers to \(spaceEntity.name)")
        
        let seatNames = ["seat_1", "seat_2"]
        for seatName in seatNames {
            // Remove any existing markers first
            if let existingMarker = findEntityDeep(named: "\(seatName)_marker", in: spaceEntity) {
                print("🗑️ Removing existing marker for \(seatName)")
                existingMarker.removeFromParent()
            }
            
            if let seatEntity = findEntityDeep(named: seatName, in: spaceEntity) {
                // Create a visible sphere
                let sphereMesh = MeshResource.generateSphere(radius: 10)
                
                // Create a material with the Metal API
                var material = SimpleMaterial()
                material.baseColor = MaterialColorParameter.color(.red)
                material.roughness = MaterialScalarParameter(1.0)
                material.metallic = MaterialScalarParameter(0.0)
                
                let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [material])
                sphereEntity.name = "\(seatName)_marker"
                
                // Position slightly above the seat to ensure visibility
                sphereEntity.position = SIMD3<Float>(0, 0, 0)
                
                seatEntity.addChild(sphereEntity)
                print("✅ Added visible sphere for \(seatName) at position \(sphereEntity.position) relative to seat")
            } else {
                print("⚠️ Could not find entity for \(seatName) in \(spaceEntity.name)")
                // Print all entities at the first level for debugging
                print("📋 Available entities at root level:")
                for (index, child) in spaceEntity.children.enumerated() {
                    print("  \(index): \(child.name)")
                }
                
                // Print full hierarchy for more detailed debugging
                print("📊 Full entity hierarchy:")
                printEntityHierarchy(spaceEntity, level: 0)
            }
        }
    }

    // Helper function to print the entire entity hierarchy
    private func printEntityHierarchy(_ entity: Entity, level: Int) {
        let indent = String(repeating: "  ", count: level)
        print("\(indent)- \(entity.name) (type: \(type(of: entity)))")
        for child in entity.children {
            printEntityHierarchy(child, level: level + 1)
        }
    }
}
