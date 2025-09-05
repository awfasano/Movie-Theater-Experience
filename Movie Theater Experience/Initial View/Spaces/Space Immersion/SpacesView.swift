// SpacesView.swift
import SwiftUI
import GroupActivities
import RealityKit
import RealityKitContent
import Combine

struct SpacesView: View {
    // Environment
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var windowManager: WindowManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Properties
    @StateObject private var spaceService = SpaceService.shared
    @StateObject private var entityWrapper = SpacesEntityWrapper.shared
    @Environment(\.realityKitScene) private var realityKitScene
    //@EnvironmentObject var audioLoader: SpatialAudioLoader
    
    @State private var navBarOpened = false
    @State private var mapOpened = false
    @State private var userVerticalOffset: Float = 0.0
    @State private var isCleaningUp = false
    @State private var isPlaying = false
    @State private var rootEntity: Entity? = nil


    // State
    @State private var selectedSpace: SpaceData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastSpaceID: Entity.ID? = nil   // memo
    @State private var previousSeatID: String = "seat_1"

    // Anchor for placing content in the scene
    @State private var anchorEntity = AnchorEntity()
    @State private var userRotationEntity = Entity()
    
    // Notification State
    @State private var notificationSentForEntityID: Entity.ID? = nil
    @State private var notificationPostTask: Task<Void, Never>? = nil
        
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive {
                cleanupView()
            }
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
        .onChange(of: appModel.selectedSpace?.currentSeat) { _, newSeat in
            if let seat = newSeat, let entity = entityWrapper.getSpaceEntity() {
                moveUserToSeat(named: seat, in: entity, animated: true)
            }
        }
        .onDisappear {
            // This robustly handles the exit sequence
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
        .onReceive(NotificationCenter.default.publisher(for: .userVerticalOffsetChanged)) { notification in
            guard let offset = notification.userInfo?["verticalOffset"] as? Float,
                  let seat = notification.userInfo?["seat"] as? String,
                  let entity = entityWrapper.getSpaceEntity() else { return }
            
            self.userVerticalOffset = offset
            // Following your working pattern, we call moveUserToSeat to update the position
            moveUserToSeat(named: seat, in: entity, from: previousSeatID, animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateAmbientVolume)) { notification in
            guard let volumePercentage = notification.userInfo?["volume"] as? Float else { return }

            // Use the AmbientAudioManager's consistent volume calculation
            let gainDB = AmbientAudioManager.percentageToDecibels(volumePercentage)

            if let rootEntity = self.rootEntity {
                AmbientAudioManager.shared.setVolume(gainDB, for: rootEntity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startAmbientAudio)) { _ in
            if let entity = rootEntity ?? entityWrapper.getSpaceEntity() {
                startAmbientAudio(in: entity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopAmbientAudio)) { _ in
            if let entity = rootEntity ?? entityWrapper.getSpaceEntity() {
                stopAmbientAudio(in: entity)
            }
        }

    }

    // MARK: - View Components
    private var mainRealityView: some View {
        RealityView { content in
            // Set up the rotation hierarchy
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
        .allowsHitTesting(false)
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
    
    private func saveVolumePreference(_ volume: Float) {
        if let spaceId = selectedSpace?.id {
            UserDefaults.standard.set(volume, forKey: "AmbientVolume_\(spaceId)")
        }
    }

    private func loadVolumePreference() -> Float {
        if let spaceId = selectedSpace?.id {
            let savedVolume = UserDefaults.standard.float(forKey: "AmbientVolume_\(spaceId)")
            // Return 75% as default if no saved preference (0.0 means no saved value)
            return savedVolume == 0.0 ? 75.0 : savedVolume
        }
        return 75.0 // Default to 75% volume instead of 0%
    }
    
    // MARK: - Complete initializeSpace Function
    @MainActor
       private func initializeSpace() async {
           print("📱 SpacesView initializeSpace called")
           
           // ALWAYS open the nav bar when SpacesView appears - this should happen every time
           windowManager.openSpaceEntryWindows(
               openWindow: openWindow,
               dismissWindow: dismissWindow
           )
           print("✅ [SpacesView] Nav bar opening requested")
           
           // Check if we're already initialized for this specific space
           if let activeSpace = appModel.currentActiveSpace,
              let selectedSpaceId = appModel.selectedSpace?.id,
              activeSpace == selectedSpaceId {
               print("✅ [SpacesView] Already initialized for space: \(activeSpace)")
               // Even though we're already initialized, we might need to rejoin or refresh
               // But we can skip the full initialization
               return
           }
           
           // If we get here, we need to do full initialization
           print("🚀 [SpacesView] Performing full initialization")
           
           // Initial State Reset
           notificationSentForEntityID = nil
           notificationPostTask?.cancel()
           isLoading = true
           errorMessage = nil
           rootEntity = nil
           
           // IMPORTANT: Reset rotations to prevent head orientation affecting particles
           anchorEntity.orientation = simd_quatf()
           userRotationEntity.orientation = simd_quatf()
           userRotation = 0  // Reset user rotation

           // Join the space
           guard let spaceId = appModel.selectedSpace?.id else {
               print("❌ Cannot initialize space, no space ID found.")
               await dismissImmersiveSpace()
               // Open tab bar again since we're exiting
               windowManager.openMainWindow(openWindow: openWindow)
               return
           }

           // Load rotation preference AFTER resetting
           loadRotationPreference()

           let success = await spaceService.joinSpace(spaceId)
           guard success else {
               print("❌ Failed to join space backend.")
               await dismissImmersiveSpace()
               appModel.currentActiveSpace = nil  // Clear active space
               windowManager.openMainWindow(openWindow: openWindow)
               return
           }
           print("✅ Successfully joined space backend: \(spaceId)")
           
           // Make sure a seat is selected
           if let cs = appModel.selectedSpace,
              (cs.currentSeat ?? "").isEmpty {
               appModel.updateSelectedSpaceSeat(to: "seat_1")
           }

           // PRIME the map *before* we show it
           if let space = appModel.selectedSpace {
               Task.detached(priority: .userInitiated) {
                   await SpaceMapResources.prime(for: space)
               }
           }

           // If the entity is already cached, attach & go
           if let currentSpace = appModel.selectedSpace,
              let entity = entityWrapper.getSpaceEntity(),
              entity.name == currentSpace.spaceName {

               self.selectedSpace = currentSpace
               self.isLoading = false
               
               // Ensure entity is in the scene
               ensureEntityIsParented(entity)
               
               // Always setup ambient audio, even from cache
               // The AmbientAudioManager will check if it's already setup
               await setupAmbientAudioFromFirebase(entity: entity, space: currentSpace)
               
               // Move to the current seat with proper rotation
               let seat = currentSpace.currentSeat ?? "seat_1"
               moveUserToSeat(named: seat, in: entity, from: nil, animated: false)
           } else {
               // Otherwise load from scratch
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

        entityWrapper.setSpaceEntity(nil)
        entityWrapper.setActiveSceneEntity(nil)
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
    
    // Set up the rotation hierarchy
    // MARK: - Modified setupRotationHierarchy to fix particle orientation issue
    private func setupRotationHierarchy(content: RealityViewContent) {
        // Reset transforms to identity before adding to scene
        anchorEntity.transform = Transform.identity
        userRotationEntity.transform = Transform.identity
        
        // Add the main anchor to the scene
        content.add(anchorEntity)
        anchorEntity.addChild(userRotationEntity)
        
        // Set the anchor at world origin initially
        anchorEntity.position = SIMD3<Float>(0, 0, 0)
        anchorEntity.orientation = simd_quatf()
    }
    
    private func handleAmbientVolumeChange(_ notification: Notification) {
        guard let volumePercentage = notification.userInfo?["volume"] as? Float,
              let rootEntity = self.rootEntity else { return }
        
        let gainDB = AmbientAudioManager.percentageToDecibels(volumePercentage)
        AmbientAudioManager.shared.setVolume(gainDB, for: rootEntity)
    }
    
    private func handleStartAmbientAudio(_ notification: Notification) {
        guard let rootEntity = self.rootEntity else { return }
        AmbientAudioManager.shared.play(entity: rootEntity)
    }
    
    private func handleStopAmbientAudio(_ notification: Notification) {
        guard let rootEntity = self.rootEntity else { return }
        AmbientAudioManager.shared.pause(entity: rootEntity)
    }
    
    @MainActor
    private func setupAmbientAudioFromFirebase(entity: Entity, space: SpaceData) async {
        // Check if space has ambient audio URL
        guard let audioURLString = space.ambient_audio,
              !audioURLString.isEmpty else {
            print("ℹ️ No ambient audio URL for space: \(space.spaceName)")
            return
        }
        
        // Find Root entity
        guard let rootEntity = findEntityDeep(named: "Root", in: entity) else {
            print("⚠️ Cannot find Root entity for ambient audio")
            return
        }
        
        do {
            // Setup ambient audio component
            try await AmbientAudioManager.shared.setupAmbientAudio(
                for: rootEntity,
                audioURLString: audioURLString
            )
            
            // Store reference for later control
            self.rootEntity = rootEntity
            
            // Load volume preference if saved
            let savedVolume = loadVolumePreference()
            if savedVolume != 0 {
                let gainDB = AmbientAudioManager.percentageToDecibels(savedVolume)
                AmbientAudioManager.shared.setVolume(gainDB, for: rootEntity)
            }
            
            // Auto-play ambient audio
            AmbientAudioManager.shared.play(entity: rootEntity)
            self.isPlaying = true
            
            print("🎵 Ambient audio setup complete and playing")
            
        } catch {
            print("❌ Failed to setup ambient audio: \(error)")
        }
    }

    
    /// Adds entity to userRotationEntity instead of anchorEntity
    @MainActor
    private func ensureEntityIsParented(_ entity: Entity) {
        // Check if the entity is already a child of the anchor
        let hasEntity = userRotationEntity.children.contains(where: { $0.id == entity.id })
        guard !hasEntity else { return }

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
                    
                    ensureEntityIsParented(entity)
                    
                    print("DEBUG: Space '\(entity.name)' was successfully loaded")
                    
                    // Setup ambient audio
                    await self.setupAmbientAudioFromFirebase(entity: entity, space: space)
                    
                    // Move to initial seat
                    let seat = space.currentSeat ?? "seat_1"
                    moveUserToSeat(named: seat, in: entity, from: nil, animated: false)

                    
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
            if let foundRoot = findEntityDeep(named: "Root", in: entity), isEntityInScene(foundRoot) {
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

        self.notificationSentForEntityID = nil
        self.notificationPostTask?.cancel()
        self.notificationPostTask = nil
        self.rootEntity = nil
    }
    
    private func updateAmbientAudioGain(in entity: Entity, gainDB: Float) {
        guard let rootEntity = self.rootEntity else {
            print("⚠️ No root entity for ambient audio")
            return
        }
        AmbientAudioManager.shared.setVolume(gainDB, for: rootEntity)
    }
    
    private func startAmbientAudio(in entity: Entity) {
        guard let rootEntity = self.rootEntity else {
            print("⚠️ No root entity for ambient audio")
            return
        }
        AmbientAudioManager.shared.play(entity: rootEntity)
        isPlaying = true
    }

    private func stopAmbientAudio(in entity: Entity) {
        guard let rootEntity = self.rootEntity else {
            print("⚠️ No root entity for ambient audio")
            return
        }
        AmbientAudioManager.shared.pause(entity: rootEntity)
        isPlaying = false
    }
    
    
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
                
                // Add to anchorEntity so participants rotate with the user's view
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

    @MainActor
        private func cleanupView() {
            guard !isCleaningUp else {
                print("⚠️ [SpacesView] Already cleaning up, skipping duplicate cleanup")
                return
            }
            isCleaningUp = true
            
            print("🧹 [SpacesView] Starting cleanup sequence")
            
            // Stop ambient audio using the manager
            if let rootEntity = self.rootEntity {
                AmbientAudioManager.shared.stop(entity: rootEntity)
            }
            
            // Reset audio state
            isPlaying = false
            self.rootEntity = nil

            // Close all space-related windows
            windowManager.closeAllSpaceWindows(dismissWindow: dismissWindow)
            
            // Leave the space if one was selected
            if let spaceId = selectedSpace?.id {
                Task {
                    await spaceService.leaveSpace(spaceId)
                    print("✅ Successfully left space: \(spaceId)")
                    
                    // Only dismiss if we're actually in the Spaces immersive space
                    if appModel.currentActiveSpace == appModel.spacesID {
                        await dismissImmersiveSpace()
                        print("✅ Immersive space dismissed")
                    }
                }
            } else {
                // Only dismiss if we're actually in an immersive space
                Task {
                    if appModel.currentActiveSpace == appModel.spacesID {
                        await dismissImmersiveSpace()
                        print("✅ Immersive space dismissed (no space selected)")
                    }
                }
            }
            
            // Save preferences
            saveRotationPreference()
            
            // Cancel all subscriptions and tasks
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
            notificationPostTask?.cancel()
            notificationPostTask = nil
            
            // Clean up entity wrapper
            Task {
                await entityWrapper.cleanup()
            }
            
            // Reset state
            navBarOpened = false
            mapOpened = false
            notificationSentForEntityID = nil
            selectedSpace = nil
            
            // Clear the scene
            anchorEntity.children.removeAll()
            userRotationEntity.children.removeAll()
            
            // Reset AppModel state - this will clear currentActiveSpace
            appModel.selectedSpace = nil
            appModel.currentActiveSpace = nil
            
            // Open main window after a short delay - WindowManager will check for duplicates
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                windowManager.openMainWindow(openWindow: openWindow)
                print("✅ [SpacesView] Cleanup complete")
                isCleaningUp = false
            }
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
    
    private func applyUserAndSeatRotation(seatRotation: simd_quatf, animated: Bool) {
        // Extract Y-axis rotation from seat
        let seatYRotation = extractYRotation(from: seatRotation)
        
        // Combine with user rotation
        let combinedRotationDegrees = userRotation + seatYRotation
        let radians = combinedRotationDegrees * .pi / 180
        let finalRotation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
        
        var currentTransform = userRotationEntity.transform
        currentTransform.rotation = finalRotation
        
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                userRotationEntity.transform = currentTransform
            }
        } else {
            userRotationEntity.transform = currentTransform
        }
    }
    
    private func extractYRotation(from quaternion: simd_quatf) -> Float {
        // Convert quaternion to euler angles and extract Y rotation
        let matrix = float3x3(quaternion)
        let yaw = atan2(matrix[0][2], matrix[2][2])
        return yaw * 180 / .pi  // Convert to degrees
    }

    
    
    private func moveUserToSeat(named seatID: String, in spaceEntity: Entity, from previousSeat: String? = nil, animated: Bool) {
        guard let seatEntity = findEntityDeep(named: seatID, in: spaceEntity) else {
            print("💺❌ Could not find seat named '\(seatID)'")
            return
        }
        
        // Ensure we have the space data to get the adjustment value
        guard let space = self.selectedSpace else {
            print("❌ Cannot move to seat, selectedSpace is nil.")
            return
        }

        // Get the seat's world transform relative to the space
        let seatWorldTransform = seatEntity.transformMatrix(relativeTo: spaceEntity)
        
        // Extract the seat's rotation (Y-axis only for horizontal rotation)
        let seatRotation = simd_quatf(seatWorldTransform)
        let seatEuler = seatRotation.angle * 180 / .pi  // Convert to degrees
        
        // Calculate the seat's position relative to the main space entity
        let seatLocalPos = seatEntity.position(relativeTo: spaceEntity)
        
        // The final target position for the anchor
        let baseAnchorPosition = -seatLocalPos - space.viewerAdjustment + SIMD3<Float>(0, self.userVerticalOffset, 0)
        
        // Combine seat rotation with user rotation
        let combinedRotation = userRotation + extractYRotation(from: seatRotation)
        let radians = combinedRotation * .pi / 180
        let rotation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
        
        // Apply the combined rotation to the position
        let rotatedFinalAnchorPosition = rotation.act(baseAnchorPosition)

        // For initial placement or non-animated transitions
        if !animated {
            anchorEntity.position = rotatedFinalAnchorPosition
            
            // Apply seat orientation to userRotationEntity
            applyUserAndSeatRotation(seatRotation: seatRotation, animated: false)
            
            print("💺 Initial placement at seat '\(seatID)' with adjustment. Anchor: \(anchorEntity.position)")
            previousSeatID = seatID
            return
        }
        
        // For animated transitions between seats
        guard let oldSeatID = previousSeat,
              let oldSeatEntity = findEntityDeep(named: oldSeatID, in: spaceEntity)
        else {
            // Fallback to non-animated placement if the old seat isn't found
            print("⚠️ Could not find previous seat '\(previousSeat ?? "nil")', snapping to new seat.")
            anchorEntity.position = rotatedFinalAnchorPosition
            applyUserAndSeatRotation(seatRotation: seatRotation, animated: false)
            previousSeatID = seatID
            return
        }

        // The starting position is the current anchor position
        let startAnchorPosition = anchorEntity.position
        
        print("🪑 Moving from seat '\(oldSeatID)' to '\(seatID)'")
        print("   Start anchor: \(startAnchorPosition)")
        print("   End anchor: \(rotatedFinalAnchorPosition)")

        withAnimation(.easeInOut(duration: 2)) {
            anchorEntity.position = rotatedFinalAnchorPosition
        }
        
        // Apply combined rotation with animation
        applyUserAndSeatRotation(seatRotation: seatRotation, animated: true)
        
        // Update the tracker for the next move
        previousSeatID = seatID
    }
    
    // Modified applyRotationToAnchor to support animation parameter
    private func applyRotationToAnchor() {
        // This now only applies user rotation adjustment
        // Seat rotation is handled in moveUserToSeat
        guard let spaceEntity = entityWrapper.getSpaceEntity(),
              let currentSeat = appModel.selectedSpace?.currentSeat,
              let seatEntity = findEntityDeep(named: currentSeat, in: spaceEntity) else {
            // If no seat, just apply user rotation
            let radians = userRotation * .pi / 180
            let rotation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
            
            var currentTransform = userRotationEntity.transform
            currentTransform.rotation = rotation
            
            withAnimation(.easeInOut(duration: 0.3)) {
                userRotationEntity.transform = currentTransform
            }
            return
        }
        
        // Get seat rotation and combine with user rotation
        let seatWorldTransform = seatEntity.transformMatrix(relativeTo: spaceEntity)
        let seatRotation = simd_quatf(seatWorldTransform)
        applyUserAndSeatRotation(seatRotation: seatRotation, animated: true)
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
            applyRotationToAnchor()
        }
    }
}

// Helper extension for matrix operations
extension float4x4 {
    var translation: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
