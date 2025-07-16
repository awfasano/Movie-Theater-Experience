import SwiftUI
import GroupActivities
import RealityKit
import RealityKitContent
import Combine

struct SpacesView: View {
    // MARK: - Properties
    @StateObject private var spaceService = SpaceService.shared
    @StateObject private var entityWrapper = SpacesEntityWrapper.shared
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.realityKitScene) private var realityKitScene
    //@EnvironmentObject var audioLoader: SpatialAudioLoader
    
    @State private var navBarOpened = false
    @State private var mapOpened = false

    
    // State
    @State private var selectedSpace: SpaceData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastSpaceID: Entity.ID? = nil   // memo
    @State private var previousSeatID: String = "seat_1"
    @State private var portalEntity: ModelEntity? = nil
    @State private var portalPaneEntity: ModelEntity? = nil // <-- ENSURE THIS LINE EXISTS




    // Anchor for placing content in the scene
    @State private var anchorEntity = AnchorEntity()
    @State private var userRotationEntity = Entity()
    
    // Notification State
    @State private var notificationSentForEntityID: Entity.ID? = nil
    @State private var notificationPostTask: Task<Void, Never>? = nil
    
    // Root entity reference
    @State private var rootEntity: Entity? = nil
    
    // Volume control visibility
    @State private var showVolumeControl = false
    
    // Combine subscriptions
    @State private var cancellables = Set<AnyCancellable>()
    
    // NEW: Add the SharePlayManager and state for participant entities
    @StateObject private var sharePlayManager = SharePlayManager.shared
    @State private var participantEntities: [Participant.ID: Entity] = [:]
    @State private var userRotation: Float = 0.0

    

    private var sharePlayParticipantManager: some View {
        Color.clear
            .onChange(of: sharePlayManager.participants) { _, newParticipants in
                updateParticipantEntities(participants: newParticipants)
            }
    }
    
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Main RealityView component
            mainRealityView
                .overlay(sharePlayParticipantManager) // Attach manager here

            // Loading and error overlays
            overlayViews


            // Volume control toggle button
            volumeToggleButton
        }
        .task {
            print("📱 SpacesView appeared")
            await initializeSpace()
        }
        .onChange(of: sharePlayManager.isSessionActive) { _, isActive in
            if isActive {
                print("SharePlay: Session just became active.")
            } else {
                print("SharePlay: Session ended.")
            }
        }
        .onChange(of: entityWrapper.getSpaceEntity()?.id) { oldId, newId in
            handleEntityIdChangeForNotification(oldId: oldId, newId: newId)
        }
        .onChange(of: appModel.viewTransparency) { _, _ in
            //updateWorldPortalTransparency()
        }
        .onChange(of: appModel.selectedSpace?.currentSeat) { _, newSeat in
            if let seat = newSeat, let entity = entityWrapper.getSpaceEntity() {
                moveUserToSeat(named: seat, in: entity, animated: true)
            }
        }
        .onDisappear {
            cleanupView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userRotationChanged)) { notification in
            guard let rotation = notification.userInfo?["rotation"] as? Float,
                  let seat = notification.userInfo?["seat"] as? String,
                  let entity = entityWrapper.getSpaceEntity() else { return }

            userRotation = rotation
            moveUserToSeat(named: seat, in: entity, animated: false)
            applyRotationToAnchor()
        }
    }

    
    // MARK: - View Components
    private var mainRealityView: some View {
        RealityView { content in
            // UPDATED: Set up the rotation hierarchy
            setupRotationHierarchy(content: content)
        } update: { _ in
            // lightweight – runs every frame
            if let e = entityWrapper.getSpaceEntity(),
               e.id != lastSpaceID {
                Task { @MainActor in
                    ensureEntityIsParented(e)
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
    
    // MARK: - Volume Control Toggle Button
    private var volumeToggleButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    showVolumeControl.toggle()
                }) {
                    Image(systemName: showVolumeControl ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(.thinMaterial, in: .circle)
                }
                .padding(.trailing)
                .padding(.bottom)
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
    
    // Add this to initializeSpace() in SpacesView.swift
    // In SpacesView.swift

    // ✅ Mark as @MainActor and async
    // MARK: - Complete initializeSpace Function

    @MainActor
    private func initializeSpace() async {
        // ① ---- Initial State Reset -------------------------------------------
        notificationSentForEntityID = nil
        notificationPostTask?.cancel()
        isLoading = true
        errorMessage = nil
        rootEntity = nil

        // ---- Join the space ---------------------------------------------------
        guard let spaceId = appModel.selectedSpace?.id else {
            print("❌ Cannot initialize space, no space ID found.")
            await dismissImmersiveSpace()
            return
        }

        // Load rotation preference if you're using it
        loadRotationPreference()

        let success = await spaceService.joinSpace(spaceId)
        guard success else {
            print("❌ Failed to join space backend.")
            await dismissImmersiveSpace()
            return
        }
        print("✅ Successfully joined space backend: \(spaceId)")

        
        //await setupWorldPortal()
        // This will set the initial state correctly
        //updateWorldPortalTransparency()
        
        // ---- Make sure a seat is selected ------------------------------------
        if let cs = appModel.selectedSpace,
           (cs.currentSeat ?? "").isEmpty {
            appModel.updateSelectedSpaceSeat(to: "seat_1")
        }

        // ② ---- PRIME the map *before* we show it -----------------------------
        if let space = appModel.selectedSpace {
            Task.detached(priority: .userInitiated) {
                await SpaceMapResources.prime(for: space)   // warm-up image + meshes
            }
        }

        // ---- If the entity is already cached, attach & go --------------------
        if let currentSpace = appModel.selectedSpace,
           let entity = entityWrapper.getSpaceEntity(),
           entity.name == currentSpace.spaceName {

            self.selectedSpace = currentSpace
            self.isLoading = false
            
            openWindowsIfNeeded()
            
            // Ensure entity is in the scene
            ensureEntityIsParented(entity)
            
            // Apply viewer offset from database

            
            // Move to the current seat and update tracker
            let seat = currentSpace.currentSeat ?? "seat_1"
            moveUserToSeat(named: seat, in: entity, from: nil, animated: false)
            
            // Load audio
            //await audioLoader.loadAudioForSpace(rootEntity: entity)
            
        } else {
            // Otherwise load from scratch
            loadSpace()
        }
    }

    // Make the function async to allow for loading
    // In SpacesView.swift

    // In SpacesView.swift

    // In SpacesView.swift

    private func setupWorldPortal() async {
        // 1. Define the portal's dimensions
        let frameThickness: Float = 0.1  // How thick the frame is
        let portalWidth: Float = 1.2     // How wide the portal opening is
        let portalHeight: Float = 1.6    // How tall the portal opening is

        // 2. Create a container for all the portal parts
        let portalContainer = Entity()
        portalContainer.name = "PortalContainer"

        // 3. Create the visible FRAME from 4 boxes
        let frameMaterial = SimpleMaterial(color: .darkGray, roughness: 0.3, isMetallic: true)

        // Top bar
        let topBar = ModelEntity(
            mesh: .generateBox(width: portalWidth + frameThickness, height: frameThickness, depth: frameThickness),
            materials: [frameMaterial]
        )
        topBar.position.y = portalHeight / 2 + (frameThickness / 2)

        // Bottom bar
        let bottomBar = ModelEntity(
            mesh: .generateBox(width: portalWidth + frameThickness, height: frameThickness, depth: frameThickness),
            materials: [frameMaterial]
        )
        bottomBar.position.y = -portalHeight / 2 - (frameThickness / 2)

        // Left bar
        let leftBar = ModelEntity(
            mesh: .generateBox(width: frameThickness, height: portalHeight, depth: frameThickness),
            materials: [frameMaterial]
        )
        leftBar.position.x = -portalWidth / 2 - (frameThickness / 2)

        // Right bar
        let rightBar = ModelEntity(
            mesh: .generateBox(width: frameThickness, height: portalHeight, depth: frameThickness),
            materials: [frameMaterial]
        )
        rightBar.position.x = portalWidth / 2 + (frameThickness / 2)

        // Add all bars to the container
        portalContainer.addChild(topBar)
        portalContainer.addChild(bottomBar)
        portalContainer.addChild(leftBar)
        portalContainer.addChild(rightBar)

        // 4. Create the PANE that shows the passthrough
        let paneMesh = MeshResource.generatePlane(width: portalWidth, height: portalHeight)
        let paneEntity = ModelEntity(mesh: paneMesh)
        paneEntity.name = "PortalPane"
        
        // This is the critical part for making occlusion work
        paneEntity.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: paneMesh.bounds.extents)]))

        portalContainer.addChild(paneEntity)

        // 5. Position the portal 2 meters in front of the user
        portalContainer.setPosition([0, 1.5, -2], relativeTo: nil)

        // 6. Add the finished portal to the scene's main anchor
        self.anchorEntity.addChild(portalContainer)

        // 7. Store a reference to the pane for material swapping
        // We don't need a reference to the frame (portalEntity) anymore unless you want to change it later.
        self.portalPaneEntity = paneEntity
        
        print("✅ Rectangular Window Portal created with a frame and a pane.")
    }


    // ADD or REPLACE with this new function to control the fade
    // In SpacesView.swift
    
    @MainActor
    private func updateWorldPortalTransparency() {
        print("SLIDER: Transparency value is now \(appModel.viewTransparency)")

        // --- V V V THIS IS THE FIX V V V ---
        // The guard should check for portalPANEEntity.
        guard let pane = self.portalPaneEntity else {
            print("DEBUG: updateWorldPortalTransparency was called, but portalPANEEntity is nil!")
            return
        }
        // --- ^ ^ ^ THIS IS THE FIX ^ ^ ^ ---

        if appModel.viewTransparency > 0 {
            print("DEBUG: Applying OcclusionMaterial to pane...")
            pane.model?.materials = [OcclusionMaterial()]
        } else {
            print("DEBUG: Applying clear UnlitMaterial to pane...")
            pane.model?.materials = [UnlitMaterial(color: .clear)]
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
        

        entityWrapper.setSpaceEntity(nil)
        entityWrapper.setActiveSceneEntity(nil)
        // UPDATED: Clear the user rotation entity instead of anchor
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
    
    // UPDATED: New method to set up the rotation hierarchy
    // UPDATED: Simpler setup function
    private func setupRotationHierarchy(content: RealityViewContent) {
        // Add the main anchor to the scene
        content.add(anchorEntity)
        anchorEntity.addChild(userRotationEntity)
    }
    
    /// UPDATED: Adds entity to userRotationEntity instead of anchorEntity
    @MainActor
    private func ensureEntityIsParented(_ entity: Entity) {
        // Check if the entity is already a child of the anchor
        let hasEntity = userRotationEntity.children.contains(where: { $0.id == entity.id })
        guard !hasEntity else { return }

        // Always ensure the anchor is clear before adding the new space
        //anchorEntity.children.removeAll()
        userRotationEntity.addChild(entity)
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
                guard space.id == self.selectedSpace?.id else {
                    if self.entityWrapper.getSpaceEntity() == nil { self.isLoading = false }
                    return
                }
                
                switch result {
                case .success(let loadedEntity):
                    self.isLoading = false
                    
                    let entity = loadedEntity.clone(recursive: true)
                    entity.name = space.spaceName
                    entity.isEnabled = true
                    
                    self.entityWrapper.setSpaceEntity(entity)
                    self.entityWrapper.setActiveSceneEntity(entity)
                    
                    openWindowsIfNeeded()
                    ensureEntityIsParented(entity)
                    
                    print("DEBUG: Space '\(entity.name)' was successfully loaded and added to the anchorEntity.")
                    // Apply viewer offset first
                    
                    // Then move to initial seat and update tracker
                    let seat = space.currentSeat ?? "seat_1"
                    moveUserToSeat(named: seat, in: entity, from: nil, animated: false)
                    
                    //await audioLoader.loadAudioForSpace(rootEntity: entity)
                    
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
        
        // Default to seat_1 if no seat is selected
        if space.currentSeat == nil || space.currentSeat!.isEmpty {
            appModel.updateSelectedSpaceSeat(to: "seat_1")
        }
        
        // Apply initial position with viewer adjustments
        if let currentSeat = space.currentSeat {
            moveUserToSeat(named: currentSeat, in: entity, animated: false)
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

        self.notificationSentForEntityID = nil
        self.notificationPostTask?.cancel()
        self.notificationPostTask = nil
        self.rootEntity = nil
    }
    
    // In SpacesView.swift

    private func updateParticipantEntities(participants: Set<Participant>) {
        // Ensure we can identify the local user to avoid creating an entity for ourselves.
        guard let localParticipantID = sharePlayManager.localParticipantID else {
            print("SharePlay: localParticipantID not available yet.")
            return
        }

        // Remove entities for participants who have left.
        for id in participantEntities.keys {
            if !participants.contains(where: { $0.id == id }) {
                participantEntities[id]?.removeFromParent()
                participantEntities.removeValue(forKey: id)
                print("SharePlay: Removed entity for participant \(id)")
            }
        }

        // Add entities for new participants.
        for participant in participants {
            guard participant.id != localParticipantID else { continue }
            
            if participantEntities[participant.id] == nil {
                let placeholder = Entity()
                placeholder.name = "participant-\(participant.id)"
                
                // UPDATED: Add to anchorEntity so participants rotate with the user's view
                anchorEntity.addChild(placeholder)
                
                participantEntities[participant.id] = placeholder
                print("SharePlay: Created placeholder for new participant \(participant.id)")
            }
        }
    }

    /// Handles updates to the local participant's spatial state
    private func updateLocalParticipantState(state: SystemCoordinator.ParticipantState?) {
        guard let state = state else { return }
        
        print("SharePlay: Local participant state updated - isSpatial: \(state.isSpatial)")
        
        // Handle local participant state changes here
        // For example, you might want to show/hide UI elements based on spatial state
    }
    
    private func handleSeatChange(oldSeat: String?, newSeat: String?) {
        guard
            let spaceEntity = entityWrapper.getSpaceEntity(),
            let seatID = newSeat
        else { return }
        
        // Use oldSeat parameter directly, not from selectedSpace
        moveUserToSeat(named: seatID, in: spaceEntity, from: oldSeat, animated: oldSeat != nil)
        
        // Update the previous seat tracker
        previousSeatID = seatID
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
        saveRotationPreference()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        notificationPostTask?.cancel()
        notificationPostTask = nil
        
        // Stop all audio playback

        Task {
            await entityWrapper.cleanup()
        }
        
        navBarOpened = false
         mapOpened = false
        
        portalEntity?.removeFromParent()
        portalEntity = nil
        appModel.viewTransparency = 0.0 // Reset slider value
        appModel.isPortalOpen = false
        
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
        if !navBarOpened {
            openWindow(id: "spaceNavBar")
            navBarOpened = true
        }
        
        if !mapOpened {
            openWindow(id: "spaceMap")
            mapOpened = true
        }
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
    
    private func moveUserToSeat(named seatID: String, in spaceEntity: Entity, from previousSeat: String? = nil, animated: Bool) {
        guard let seatEntity = findEntityDeep(named: seatID, in: spaceEntity) else {
            print("💺❌ Could not find seat named '\(seatID)'")
            return
        }
        
        // Ensure we have the space data to get the adjustment value.
        guard let space = self.selectedSpace else {
            print("❌ Cannot move to seat, selectedSpace is nil.")
            return
        }

        // Calculate the seat's position relative to the main space entity.
        let seatLocalPos = seatEntity.position(relativeTo: spaceEntity)
        
        // The final target position for the anchor.
        // This moves the seat to the origin AND applies the viewer offset.
        let finalAnchorPosition = -seatLocalPos - space.viewerAdjustment

        // Create a rotation quaternion from the user's rotation
        let radians = userRotation * .pi / 180
        let rotation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))

        // Rotate the final position by the user's rotation
        let rotatedFinalAnchorPosition = rotation.act(finalAnchorPosition)


        // For initial placement or non-animated transitions
        if !animated {
            anchorEntity.position = rotatedFinalAnchorPosition
            print("💺 Initial placement at seat '\(seatID)' with adjustment. Anchor: \(anchorEntity.position)")
            previousSeatID = seatID
            return
        }
        
        // For animated transitions between seats
        guard let oldSeatID = previousSeat,
              let oldSeatEntity = findEntityDeep(named: oldSeatID, in: spaceEntity)
        else {
            // Fallback to non-animated placement if the old seat isn't found.
            print("⚠️ Could not find previous seat '\(previousSeat ?? "nil")', snapping to new seat.")
            anchorEntity.position = rotatedFinalAnchorPosition
            previousSeatID = seatID
            return
        }

        // The starting position is the current anchor position.
        let startAnchorPosition = anchorEntity.position
        
        print("🪑 Moving from seat '\(oldSeatID)' to '\(seatID)'")
        print("   Start anchor: \(startAnchorPosition)")
        print("   End anchor: \(rotatedFinalAnchorPosition)")

        withAnimation(.easeInOut(duration: 2)) {
            anchorEntity.position = rotatedFinalAnchorPosition
        }
        
        // Update the tracker for the next move.
        previousSeatID = seatID
    }
    
    // Modified applyRotationToAnchor to support animation parameter
    private func applyUserRotationToAnchor(animated: Bool = true) {
        let radians = userRotation * .pi / 180
        let userRotationQuat = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
        
        // Get current transform and update only the rotation
        var currentTransform = anchorEntity.transform
        currentTransform.rotation = userRotationQuat
        
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                anchorEntity.transform = currentTransform
            }
        } else {
            anchorEntity.transform = currentTransform
        }
    }


    // Update the existing applyRotationToAnchor to use the new method
    private func applyRotationToAnchor() {
        let radians = userRotation * .pi / 180
        let rotation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
        
        // Only apply rotation, preserve position
        var currentTransform = userRotationEntity.transform
        currentTransform.rotation = rotation
        
        withAnimation(.easeInOut(duration: 0.3)) {
            userRotationEntity.transform = currentTransform
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
    
    private func updateAnchorRotation() {
        let radians = userRotation * .pi / 180
        let rotation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
        
        withAnimation(.easeInOut(duration: 0.3)) {
            anchorEntity.orientation = rotation
        }
    }

    // Optional: Save rotation preference per space
    private func saveRotationPreference() {
        if let spaceId = selectedSpace?.id {
            UserDefaults.standard.set(userRotation, forKey: "SpaceRotation_\(spaceId)")
        }
    }

    private func loadRotationPreference() {
        if let spaceId = selectedSpace?.id {
            userRotation = UserDefaults.standard.float(forKey: "SpaceRotation_\(spaceId)")
            applyRotationToAnchor() // UPDATED
        }
    }
    
}


// Helper extension for matrix operations
extension float4x4 {
    var translation: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
