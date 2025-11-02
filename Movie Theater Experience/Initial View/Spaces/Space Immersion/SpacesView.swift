// SpacesView.swift
import SwiftUI
import GroupActivities
import RealityKit
import RealityKitContent
import Combine

struct SpacesView: View {
    // Environment
    @Environment(AppModel.self) private var appModel // NEW
    @EnvironmentObject private var windowManager: WindowManager
    @Environment(\.openWindow) private var openWindowAction // NEW
    @Environment(\.dismissWindow) private var dismissWindowAction // NEW
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Properties
    @StateObject private var spaceService = SpaceService.shared
    @EnvironmentObject private var drawingViewModel: SpaceDrawingViewModel
    @EnvironmentObject private var entityWrapper: SpacesEntityWrapper // NEW
    @Environment(\.realityKitScene) private var realityKitScene
    //@EnvironmentObject var audioLoader: SpatialAudioLoader
    
    private let navBarAttachmentTag = "navBarReopenAttachment"

    
    @State private var navBarOpened = false
    @State private var mapOpened = false
    @State private var userVerticalOffset: Float = 0.0
    @State private var isCleaningUp = false
    @State private var isPlaying = false
    @State private var rootEntity: Entity? = nil
    
    @State private var footButtonEntity: Entity? = nil
    @State private var hasCleanedUp = false



    // State
    @State private var selectedSpace: SpaceData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastSpaceID: Entity.ID? = nil   // memo
    @State private var previousSeatID: String = "seat_1"

    // Anchor for placing content in the scene
    @State private var anchorEntity = AnchorEntity()
    @State private var userRotationEntity = Entity()
    @State private var headAnchor = AnchorEntity(.head) // head-locked anchor

    
    // Notification State
    @State private var notificationSentForEntityID: Entity.ID? = nil
    @State private var notificationPostTask: Task<Void, Never>? = nil
    // Add near the top of SpacesView
    @State private var wasPlayingBeforeOverlay = false

        
    // Volume control visibility
    
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

            // Drawing canvas overlay
            VStack {
                Spacer()
                SpaceDrawingCanvasView(viewModel: drawingViewModel)
                    .frame(maxWidth: 1500, maxHeight: 1500)
                    .padding(.bottom, 72)
            }

            // Loading and error overlays
            overlayViews

            // Volume control toggle button
        }
        .task {
            print("📱 SpacesView appeared")
            
            // Optimization: Prevent initialization during flicker if the app is inactive (e.g., Digital Crown press).
            if scenePhase != .active {
                 print("⚠️ [SpacesView] Appeared but scenePhase is \(scenePhase). Skipping initialization.")
                 return
            }
            
            hasCleanedUp = false
            await initializeSpace()
        }

        .onChange(of: scenePhase, perform: handleScenePhaseChange)

        .onChange(of: sharePlayManager.isSessionActive) { _, isActive in
            if isActive {
                print("SharePlay: Session just became active.")
            } else {
                print("SharePlay: Session ended.")
            }
        }
        .onChange(of: selectedSpace?.id) { _, _ in
            drawingViewModel.activateSpace(selectedSpace)
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
            print("📱 SpacesView disappeared")
            // Only cleanup if we haven't already
            if !hasCleanedUp {
                cleanupView()
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .immersiveSpaceWillDismiss)) { _ in
            print("🚪 [SpacesView] Received immersive space dismissal notification")
            // Ensure cleanup happens if triggered by notification (e.g., from NavBar button press)
             if !hasCleanedUp {
                 cleanupView()
             }
        }
    }

    // MARK: - View Components
    private var mainRealityView: some View {
        RealityView { content, attachments in
            // existing world/content setup
            setupRotationHierarchy(content: content)

            // Add the head-locked anchor once
            if headAnchor.parent == nil {
                content.add(headAnchor)
            }

            // Get the attachment entity and parent it to the head anchor
            // No billboard needed when head-locked
            if let attachmentEntity = attachments.entity(for: navBarAttachmentTag) {
                // Keep it comfortably in view
                attachmentEntity.position = SIMD3<Float>(0.1, -0.30, -0.75)

                // Parent to the head anchor (so it follows the head)
                if headAnchor.parent == nil { content.add(headAnchor) }
                if attachmentEntity.parent !== headAnchor {
                    headAnchor.addChild(attachmentEntity)
                }
            }

        } update: { _, attachments in
            // Keep the button in view even if pose changes rapidly
            if let attachmentEntity = attachments.entity(for: navBarAttachmentTag) {
                attachmentEntity.position = SIMD3<Float>(0.1, -0.30, -0.75)
            }
        } attachments: {
            Attachment(id: navBarAttachmentTag) { navBarReopenButton }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    
    private var navBarReopenButton: some View {
        let isOpen = windowManager.isWindowOpen(.spaceNavBar)
        return Button(action: { handleReopenNavBar() }) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .resizable().scaledToFit().frame(width: 40, height: 40)
                .padding()
        }
        .glassBackgroundEffect()
        .buttonStyle(.borderless)
        // Instead of fully hiding, fade + disable taps when NavBar is open
        .opacity(isOpen ? 0.0 : 1.0)
        .allowsHitTesting(!isOpen)
        .animation(.easeInOut(duration: 0.2), value: isOpen)
        .accessibilityLabel("Reopen Navigation Bar")
    }

    
    private func handleReopenNavBar() {
        print("👆 Attachment button tapped - requesting NavBar open")
        // WindowManager handles the check for duplicates internally.
        // Use the renamed openWindowAction.
        windowManager.openWindow(.spaceNavBar, openAction: openWindowAction)
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
    
    
    // Add these helpers inside SpacesView
    @MainActor
     private func handleScenePhaseChange(_ phase: ScenePhase) {
         switch phase {
         case .active:
             RenderGuard.shared.setActive(true)
             if wasPlayingBeforeOverlay, let root = rootEntity {
                 AmbientAudioManager.shared.play(entity: root)
                 isPlaying = true
                 NotificationCenter.default.post(
                     name: .ambientAudioStateChanged,
                     object: nil,
                     userInfo: ["isPlaying": true]
                 )
             }

         case .inactive:
             RenderGuard.shared.setActive(false)
             if let root = rootEntity {
                 wasPlayingBeforeOverlay = isPlaying
                 AmbientAudioManager.shared.pause(entity: root)
                 isPlaying = false
                 NotificationCenter.default.post(
                     name: .ambientAudioStateChanged,
                     object: nil,
                     userInfo: ["isPlaying": false]
                 )
             }

         case .background:
             print("🌍 [SpacesView] Moving to background - checking if immersive space dismissed")
             // Only cleanup if we haven't already
             if !hasCleanedUp {
                 cleanupView()
             }

         @unknown default:
             break
         }
     }

    
    // MARK: - Complete initializeSpace Function
    // MARK: - Complete initializeSpace Function
    @MainActor
    private func initializeSpace() async {
        print("📱 SpacesView initializeSpace called")

        // 1) Open space entry windows (NavBar) and close TabBar.
        windowManager.openSpaceEntryWindows(
            openAction: openWindowAction,
            dismissAction: dismissWindowAction
        )
        print("✅ [SpacesView] Nav bar opening requested")

        // 2) If we already initialized for this specific space, avoid any reload.
        if let activeSpace = appModel.currentActiveSpace,
           let selectedSpaceId = appModel.selectedSpace?.id,
           activeSpace == selectedSpaceId
        {
            print("✅ [SpacesView] Already initialized for space: \(activeSpace).")
            // Still ensure parenting (idempotent) in case RealityView re-updated.
            if let e = entityWrapper.getSpaceEntity() {
                ensureEntityIsParented(e)
            }
            return
        }

        // 3) Initial state reset
        print("🚀 [SpacesView] Performing full initialization")
        notificationSentForEntityID = nil
        notificationPostTask?.cancel()
        isLoading = true
        errorMessage = nil
        rootEntity = nil

        // 4) Reset anchors and local rotation state
        anchorEntity.orientation = simd_quatf()
        userRotationEntity.orientation = simd_quatf()
        userRotation = 0

        // 5) Validate selected space id + join backend
        guard let spaceId = appModel.selectedSpace?.id else {
            print("❌ Cannot initialize space, no space ID found.")
            await windowManager.performEmergencyExit(
                dismissAction: dismissWindowAction,
                openAction: openWindowAction,
                dismissImmersiveSpace: { await self.dismissImmersiveSpace() }
            )
            return
        }

        // Load per-space rotation AFTER resetting transforms
        loadRotationPreference()

        let joined = await spaceService.joinSpace(spaceId)
        guard joined else {
            print("❌ Failed to join space backend.")
            appModel.currentActiveSpace = nil
            await windowManager.performEmergencyExit(
                dismissAction: dismissWindowAction,
                openAction: openWindowAction,
                dismissImmersiveSpace: { await self.dismissImmersiveSpace() }
            )
            return
        }
        print("✅ Successfully joined space backend: \(spaceId)")

        // 6) Ensure a default seat exists
        if let cs = appModel.selectedSpace,
           (cs.currentSeat ?? "").isEmpty {
            appModel.updateSelectedSpaceSeat(to: "seat_1")
        }

        // 7) Prime map resources (if used)
        if let space = appModel.selectedSpace {
            Task.detached(priority: .userInitiated) {
                await SpaceMapResources.prime(for: space)
            }
        }

        // 8) EARLY-RETURN on cached entity path (prevents duplicate loads)
        if let currentSpace = appModel.selectedSpace,
           let cached = entityWrapper.getSpaceEntity(),
           cached.name == currentSpace.spaceName
        {
            self.selectedSpace = currentSpace
            self.isLoading = false

            ensureEntityIsParented(cached)
            await setupAmbientAudioFromFirebase(entity: cached, space: currentSpace)
            
            let seat = currentSpace.currentSeat ?? "seat_1"
            moveUserToSeat(named: seat, in: cached, animated: false)
            return  // <-- critical: do not drop into load path
        }

        // 9) Otherwise, proceed to load (single-source path)
        loadSpace()
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
    
    @MainActor
    private func ensureRootEntity(using fallbackSpaceEntity: Entity?) -> Entity? {
        if let root = self.rootEntity, isEntityInScene(root) {
            return root
        }
        if let spaceEntity = fallbackSpaceEntity,
           let foundRoot = findEntityDeep(named: "Root", in: spaceEntity) {
            self.rootEntity = foundRoot
            return foundRoot
        }
        return nil
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
        drawingViewModel.configureSceneRoot(userRotationEntity)
        
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
        // 1) If we’ve already parented this exact entity, bail.
        if let last = lastSpaceID, last == entity.id {
            return
        }

        // 2) Remove any previous space children (defensive).
        //    We’ll treat any child whose name matches the current spaceName as a prior instance.
        if let spaceName = selectedSpace?.spaceName {
            userRotationEntity.children
                .filter { $0.name == spaceName }
                .forEach { $0.removeFromParent() }
        }

        // 3) Also remove by prior tracked ID (if we have it).
        if let last = lastSpaceID,
           let oldChild = userRotationEntity.children.first(where: { $0.id == last }) {
            oldChild.removeFromParent()
        }

        // 4) Parent exactly one instance.
        userRotationEntity.addChild(entity)

        // 5) Remember which one we parented.
        lastSpaceID = entity.id
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
                    self.drawingViewModel.activateSpace(space)
                    
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
    
    // MARK: - System Dismissal Handler
    @MainActor
    private func ensureWindowsClosedAfterSystemDismissal() async {
        // Check if any space windows are still open after system dismissal
        let spaceWindowsOpen = windowManager.spaceWindowTypes.contains { windowType in
            windowManager.isWindowOpen(windowType)
        }
        
        if spaceWindowsOpen {
            print("🚨 [SpacesView] Space windows still open after system dismissal - force closing")
            
            // Force close all space windows
            for windowType in windowManager.spaceWindowTypes {
                if windowManager.isWindowOpen(windowType) {
                    dismissWindowAction(id: windowType.rawValue)
                    windowManager.untrackWindow(windowType)
                }
            }
            
            // Close browser windows too
            windowManager.closeAllWebBrowsers(dismissAction: dismissWindowAction)
            
            // Wait a moment then open main window
            try? await Task.sleep(for: .milliseconds(300))
            
            // Only open main window if it's not already open
            if !windowManager.isWindowOpen(.mainContent) {
                windowManager.openMainWindow(openAction: openWindowAction)
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
        
        // Notify the nav bar about the state change
        NotificationCenter.default.post(
            name: .ambientAudioStateChanged,
            object: nil,
            userInfo: ["isPlaying": true]
        )
    }

    private func stopAmbientAudio(in entity: Entity) {
        guard let rootEntity = self.rootEntity else {
            print("⚠️ No root entity for ambient audio")
            return
        }
        AmbientAudioManager.shared.pause(entity: rootEntity)
        isPlaying = false
        
        // Notify the nav bar about the state change
        NotificationCenter.default.post(
            name: .ambientAudioStateChanged,
            object: nil,
            userInfo: ["isPlaying": false]
        )
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

    // MARK: - Cleanup View
    // MARK: - Cleanup View
    @MainActor
    private func cleanupView() {
        // Local guard for the content cleanup part
        guard !isCleaningUp else {
            print("🧹 [SpacesView] Cleanup already in progress locally, skipping.")
            return
        }
        
        // Set BOTH flags immediately
        isCleaningUp = true
        hasCleanedUp = true
        
        print("cleaning up audio")
        AudioService.shared.cleanup()

        print("🧹 [SpacesView] Cleaning up immersive content and resetting currentActiveSpace.")
        
        // Post the dismissal notification
        NotificationCenter.default.post(name: .immersiveSpaceWillDismiss, object: nil)
        
        // 1. Reset AppModel state
        appModel.currentActiveSpace = nil
        
        drawingViewModel.cleanup()
        // 2. Clean up RealityKit content (Stop audio, remove entities, reset trackers)
        // (Keep the existing content cleanup logic here)
        if let e = entityWrapper.getSpaceEntity() {
            e.removeFromParent()
        }
        entityWrapper.setSpaceEntity(nil)
        entityWrapper.setActiveSceneEntity(nil)
        
        // Clear scene graph roots
        userRotationEntity.children.removeAll()
        anchorEntity.children.removeAll()
        
        // Reset trackers
        lastSpaceID = nil
        rootEntity = nil
        selectedSpace = nil
        notificationSentForEntityID = nil
        notificationPostTask?.cancel()
        notificationPostTask = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        // 3. Trigger the robust window management logic in WindowManager
        print("🧹 [SpacesView] Triggering WindowManager.handleImmersiveSpaceExit.")
        windowManager.handleImmersiveSpaceExit(
            openAction: openWindowAction,
            dismissAction: dismissWindowAction
        )
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
                material.color = .init(tint: .red, texture: nil)
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


// RenderGuard.swift
@MainActor
final class RenderGuard {
    static let shared = RenderGuard()
    private(set) var isActive = true
    func setActive(_ active: Bool) { isActive = active }
}

