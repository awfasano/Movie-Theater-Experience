import SwiftUI
import RealityKit
import Combine

struct SpacesView: View {
    // MARK: - Properties
    @ObservedObject var spaceService = SpaceService.shared
    @ObservedObject var entityWrapper = SpacesEntityWrapper.shared
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.realityKitScene) private var realityKitScene
    
    // State
    @State private var selectedSpace: SpaceData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDebugInfo = true
    @State private var realityViewUpdateCounter = 0

    // Anchor for placing content in the scene
    @State private var anchorEntity = AnchorEntity()

    // Combine subscriptions
    @State private var cancellables = Set<AnyCancellable>()

    // Notification State
    @State private var notificationSentForEntityID: Entity.ID? = nil
    @State private var notificationPostTask: Task<Void, Never>? = nil
    
    // Debug logs
    @State private var notificationLogs: [String] = []
    
    // Root entity reference - track the actual Root entity once found
    @State private var rootEntity: Entity? = nil
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Loading and error overlay UI
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

            // The core RealityKit view
            RealityView { content in
                // Initial setup: Add the anchor to the RealityView's scene content
                print("➡️ RealityView make: Adding anchor entity")
                content.add(anchorEntity)
            } update: { content in
                print("➡️ RealityView update: triggered (Counter: \(realityViewUpdateCounter))")
                
                // Ensure the correct entity is visually present
                let currentEntityInWrapper = entityWrapper.getSpaceEntity()
                let currentEntityID = currentEntityInWrapper?.id
                let anchorHasCorrectChild = anchorEntity.children.contains { $0.id == currentEntityID }
                let anchorShouldBeEmpty = currentEntityInWrapper == nil && !anchorEntity.children.isEmpty
                
                print("   - Update Check: Entity ID = \(currentEntityID?.description ?? "nil"), Anchor Has Correct Child = \(anchorHasCorrectChild), Anchor Should Be Empty = \(anchorShouldBeEmpty)")
                
                if let entity = currentEntityInWrapper, !anchorHasCorrectChild {
                    print("   - Update Action: Entity '\(entity.name)' found but not child. Adding/Replacing in anchor.")
                    
                    guard let space = getSpaceForScene(for: entity.id) else {
                        print("      - Error: Could not get SpaceData for entity '\(entity.name)' in update. Cannot position.")
                        if !anchorEntity.children.isEmpty { anchorEntity.children.removeAll() }
                        return
                    }
                    
                    if !anchorEntity.children.isEmpty {
                        print("      - Clearing existing anchor children.")
                        anchorEntity.children.removeAll()
                    }
                    
                    // IMPORTANT - Extract the root child directly rather than searching for it by name
                    // This approach avoids name-based search which isn't working based on your logs
                    let rootCandidate = entity.children.first { $0.name == "Root" }
                    if let foundRoot = rootCandidate {
                        Task { @MainActor in
                            print("🔍 DEBUG: Found Root entity at top level (ID: \(foundRoot.id))")
                            addLog("🔍 Found Root entity at top level (ID: \(foundRoot.id))")
                            self.rootEntity = foundRoot
                        }
                    } else {
                        // Fallback to deeper search
                        if let foundRoot = findEntityDeep(named: "Root", in: entity) {
                            Task { @MainActor in
                                print("🔍 DEBUG: Found Root entity deeper in hierarchy (ID: \(foundRoot.id))")
                                addLog("🔍 Found Root entity deeper in hierarchy (ID: \(foundRoot.id))")
                                self.rootEntity = foundRoot
                            }
                        } else {
                            Task { @MainActor in
                                print("⚠️ DEBUG: Could NOT find Root entity in hierarchy")
                                addLog("⚠️ Could NOT find Root entity in hierarchy")
                                self.rootEntity = nil
                                
                                // Try forcing a fixed name of "root" (lowercase) as some exporters change the case
                                if let altRoot = findEntityDeep(named: "root", in: entity) {
                                    print("🔍 DEBUG: Found lowercase 'root' entity instead (ID: \(altRoot.id))")
                                    addLog("🔍 Found lowercase 'root' entity instead")
                                    self.rootEntity = altRoot
                                }
                            }
                        }
                    }
                    
                    entity.isEnabled = true
                    enableAllEntities(in: entity)
                    let adjustment = SIMD3<Float>(
                        Float(space.viewerXAdjustment),
                        Float(space.viewerYAdjustment),
                        Float(space.viewerZAdjustment)
                    )
                    entity.position = adjustment
                    entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
                    print("      - Configured entity '\(entity.name)' position: \(adjustment)")
                    
                    anchorEntity.addChild(entity)
                    print("      - Added entity '\(entity.name)' (ID: \(entity.id)) to anchor.")
                    
                    // IMPORTANT: Dump the entire hierarchy to help debug
                    Task { @MainActor in
                        print("📊 ENTITY HIERARCHY DUMP:")
                        dumpEntity(entity, level: 0)
                        
                        // Get list of all entity names
                        let names = collectEntityNames(entity)
                        addLog("📋 Entity names: \(names.prefix(10).joined(separator: ", "))\(names.count > 10 ? "..." : "")")
                    }
                } else if anchorShouldBeEmpty {
                    print("   - Update Action: No entity in wrapper, but anchor not empty. Clearing anchor children.")
                    anchorEntity.children.removeAll()
                    Task { @MainActor in
                        self.rootEntity = nil
                    }
                }
            }
            .id(realityViewUpdateCounter)
            .ignoresSafeArea()

            // Debug overlay UI
            if showDebugInfo {
                debugOverlay
            }
        }
        .onAppear {
            print("📱 SpacesView appeared")
            initializeSpace()
        }
        .onChange(of: entityWrapper.getSpaceEntity()?.id) { oldId, newId in
            handleEntityIdChangeForNotification(oldId: oldId, newId: newId)
        }
        .onDisappear {
            print("📱 SpacesView disappeared")
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
            notificationPostTask?.cancel()
            notificationPostTask = nil
            Task {
                await entityWrapper.cleanup()
                print("   - Wrapper cleanup called.")
            }
            notificationSentForEntityID = nil
            selectedSpace = nil
            rootEntity = nil
            anchorEntity.children.removeAll()
            print("   - Cleaned up view state.")
        }
    }
    
    // MARK: - Logging and Debug Helpers
    
    private func addLog(_ message: String) {
        if notificationLogs.count > 50 {
            notificationLogs.removeFirst(10)
        }
        notificationLogs.append(message)
    }
    
    private func dumpEntity(_ entity: Entity, level: Int) {
        let indent = String(repeating: "  ", count: level)
        print("\(indent)- \(entity.name) (ID: \(entity.id), Children: \(entity.children.count))")
        
        for child in entity.children {
            dumpEntity(child, level: level + 1)
        }
    }
    
    private func collectEntityNames(_ entity: Entity) -> [String] {
        var names = [entity.name]
        
        for child in entity.children {
            names.append(contentsOf: collectEntityNames(child))
        }
        
        return names
    }
    
    // MARK: - Initialization and Loading
    
    private func initializeSpace() {
        print("🔄 Initializing Space...")
        notificationSentForEntityID = nil
        notificationPostTask?.cancel()
        notificationPostTask = nil
        isLoading = false
        errorMessage = nil
        rootEntity = nil
        notificationLogs.removeAll()
        addLog("🔄 Space initialization started")
        
        if let currentSelectedSpace = appModel.selectedSpace,
           let entity = entityWrapper.getSpaceEntity(),
           entity.name == currentSelectedSpace.spaceName {
            print("✅ Found entity '\(entity.name)' matching selected space '\(currentSelectedSpace.spaceName)'.")
            selectedSpace = currentSelectedSpace
            handleEntityIdChangeForNotification(oldId: nil, newId: entity.id)
            realityViewUpdateCounter += 1
            openWindowsIfNeeded()
            addLog("✅ Reusing existing entity for space: \(currentSelectedSpace.spaceName)")
        } else {
            print("ℹ️ No existing entity matching current state (\(appModel.selectedSpace?.spaceName ?? "None selected")), starting load process.")
            addLog("ℹ️ Starting new space load process")
            loadSpace()
        }
    }
    
    private func loadSpace() {
        print("🔄 Starting loadSpace...")
        notificationSentForEntityID = nil
        isLoading = true
        errorMessage = nil
        notificationPostTask?.cancel()
        notificationPostTask = nil
        rootEntity = nil
        
        entityWrapper.setSpaceEntity(nil)
        entityWrapper.setActiveSceneEntity(nil)
        anchorEntity.children.removeAll()
        realityViewUpdateCounter += 1
        openWindowsIfNeeded()
        
        let spaceToLoad = appModel.selectedSpace ?? spaceService.spaces.first
        self.selectedSpace = spaceToLoad
        
        if let space = spaceToLoad {
            print("   - Attempting to load space: \(space.spaceName)")
            addLog("🔄 Loading space: \(space.spaceName)")
            loadSpaceEntity(for: space)
        } else {
            print("   - No space available locally, fetching from service...")
            addLog("🔄 Fetching spaces from service")
            fetchSpacesAndLoadFirst()
        }
    }
    
    private func fetchSpacesAndLoadFirst() {
        spaceService.fetchSpaces()
        spaceService.$spaces
            .dropFirst()
            .first(where: { !$0.isEmpty })
            .sink { fetchedSpaces in
                print("   - Spaces fetched via Combine, count: \(fetchedSpaces.count)")
                self.addLog("📥 Fetched \(fetchedSpaces.count) spaces")
                
                guard let firstFetchedSpace = fetchedSpaces.first else {
                    Task { @MainActor in
                        self.addLog("❌ No spaces found")
                        self.handleLoadError("Failed to load space data (empty list fetched).")
                    }
                    return
                }
                if self.selectedSpace == nil {
                    self.selectedSpace = firstFetchedSpace
                    print("   - Using first fetched space: \(firstFetchedSpace.spaceName)")
                    self.addLog("🔄 Using first fetched space: \(firstFetchedSpace.spaceName)")
                    self.loadSpaceEntity(for: firstFetchedSpace)
                } else {
                    print("   - A space (\(self.selectedSpace?.spaceName ?? "unknown")) was selected while fetch completed. Load assumed handled.")
                    self.addLog("ℹ️ Using already selected space: \(self.selectedSpace?.spaceName ?? "unknown")")
                }
            }
            .store(in: &cancellables)
     }
    
    private func loadSpaceEntity(for space: SpaceData) {
        print("🔄 Loading entity asset for space: \(space.spaceName)")
        isLoading = true
        
        spaceService.loadSpace(from: space) { result in
            Task { @MainActor in
                guard space.id == self.selectedSpace?.id else {
                    print("⚠️ Stale load completed for \(space.spaceName). Current selection: \(self.selectedSpace?.spaceName ?? "nil"). Discarding result.")
                    self.addLog("⚠️ Discarding stale load result for \(space.spaceName)")
                    if entityWrapper.getSpaceEntity() == nil { self.isLoading = false }
                    return
                }
                
                switch result {
                case .success(let loadedRawEntity):
                    self.isLoading = false
                    print("✅ Entity loaded successfully for space: \(space.spaceName)")
                    self.addLog("✅ Entity loaded successfully for: \(space.spaceName)")
                    
                    let clonedEntity = loadedRawEntity.clone(recursive: true)
                    clonedEntity.name = space.spaceName
                    clonedEntity.isEnabled = true
                    
                    // Look for Root entity immediately after loading
                    if let rootCandidate = self.findEntityDeep(named: "Root", in: clonedEntity) {
                        print("🔍 DEBUG: Found Root entity during loading (ID: \(rootCandidate.id))")
                        self.addLog("🔍 Found Root entity during loading")
                        self.rootEntity = rootCandidate
                    } else {
                        print("⚠️ DEBUG: Could NOT find Root entity during loading")
                        self.addLog("⚠️ No Root entity found during loading")
                        self.rootEntity = nil
                    }
                    
                    self.notificationSentForEntityID = nil
                    self.notificationPostTask?.cancel()
                    self.notificationPostTask = nil
                    
                    entityWrapper.setEntity(clonedEntity)
                    entityWrapper.setSpaceEntity(clonedEntity)
                    entityWrapper.setActiveSceneEntity(clonedEntity)
                    print("   - Entity set in wrapper. onChange will now trigger notification logic.")
                    self.addLog("🔄 Entity set in wrapper - will trigger notification")
                    
                case .failure(let error):
                    self.addLog("❌ Failed to load space: \(error.localizedDescription)")
                    self.handleLoadError("Failed to load \(space.spaceName): \(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor private func handleLoadError(_ message: String) {
        print("❌ Load Error: \(message)")
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
        self.realityViewUpdateCounter += 1
    }
    
    // MARK: - Notification Triggering
    
    private func handleEntityIdChangeForNotification(oldId: Entity.ID?, newId: Entity.ID?) {
        print("ℹ️ handleEntityIdChangeForNotification: Triggered by ID change: \(oldId?.description ?? "nil") -> \(newId?.description ?? "nil")")
        addLog("ℹ️ Entity ID changed: \(oldId?.description ?? "nil") -> \(newId?.description ?? "nil")")
        
        notificationPostTask?.cancel()
        notificationPostTask = nil
        
        Task { @MainActor in realityViewUpdateCounter += 1 }
        
        guard let currentNewId = newId else {
            print("   - New ID is nil. No notification scheduled. Resetting flag.")
            addLog("ℹ️ No notification - new ID is nil")
            Task { @MainActor in self.notificationSentForEntityID = nil }
            return
        }
        
        guard oldId != currentNewId else {
            print("   - onChange detected same ID (\(currentNewId)). No action needed.")
            addLog("ℹ️ No notification - same entity ID")
            return
        }
        
        Task { @MainActor in
            self.notificationSentForEntityID = nil
            print("   - Notification flag reset. Scheduling notification task for new Entity ID: \(currentNewId)")
            addLog("🔄 Scheduling notification for ID: \(currentNewId)")
            
            // Create a new task for posting the notification with delay
            self.notificationPostTask = Task { @MainActor in
                print("   - Notification Task (ID:\(currentNewId)): Started.")
                addLog("🚀 Starting notification task")
                
                // Wait for 1 second to ensure the interaction system is ready
                // (per Apple's recommendation to wait at least half a second)
                do {
                    print("⏱️ Waiting 1000ms before sending notification")
                    addLog("⏱️ Waiting 1000ms for scene to stabilize")
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    print("   - Notification Task (ID:\(currentNewId)): Sleep interrupted.")
                    addLog("❌ Wait interrupted: \(error.localizedDescription)")
                    return
                }
                
                guard !Task.isCancelled else {
                    print("   - Notification Task (ID:\(currentNewId)): Cancelled before sending.")
                    addLog("❌ Task cancelled before sending")
                    return
                }
                
                // Get the RealityKit scene from the environment
                guard let scene = realityKitScene else {
                    print("❌ No RealityKit scene available from environment")
                    addLog("❌ No RealityKit scene available")
                    return
                }
                
                print("✅ Got RealityKit scene from environment")
                addLog("✅ Got RealityKit scene from environment")
                
                // IMPORTANT: Check if our anchor entity is connected to the scene
                if anchorEntity.scene != nil {
                    print("✅ Anchor entity is connected to scene")
                    addLog("✅ Anchor entity is connected to scene")
                } else {
                    print("⚠️ Anchor entity is NOT connected to scene")
                    addLog("⚠️ Anchor entity NOT connected to scene")
                }
                
                // IMPORTANT: Use our cached Root entity if available
                if let trackedRoot = self.rootEntity, isEntityInScene(trackedRoot) {
                    print("✅ Using tracked Root entity (ID: \(trackedRoot.id))")
                    addLog("✅ Using tracked Root entity (ID: \(trackedRoot.id))")
                    
                    // Try to send notification directly to the Root entity
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RealityKit.NotificationTrigger"),
                        object: nil,
                        userInfo: [
                            "RealityKit.NotificationTrigger.Scene": scene,
                            "RealityKit.NotificationTrigger.Entity": trackedRoot,
                            "RealityKit.NotificationTrigger.Identifier": "loop"
                        ]
                    )
                    
                    print("📬 Posted notification with Root entity reference")
                    addLog("📬 Posted notification with Root entity reference")
                } else {
                    // If we don't have a cached Root entity, try to find it in the current space
                    print("⚠️ No tracked Root entity available, searching again")
                    addLog("⚠️ No tracked Root entity available")
                    
                    // Try both approaches to find Root
                    if let entity = entityWrapper.getSpaceEntity() {
                        var foundRoot: Entity? = nil
                        
                        // First try direct child with "Root" name
                        let directRoot = entity.children.first { $0.name == "Root" }
                        if let directRoot = directRoot {
                            foundRoot = directRoot
                            print("🔍 Found Root as direct child")
                            addLog("🔍 Found Root as direct child")
                        } else {
                            // Then try with recursive search
                            foundRoot = findEntityDeep(named: "Root", in: entity)
                            if foundRoot != nil {
                                print("🔍 Found Root via deep search")
                                addLog("🔍 Found Root via deep search")
                            } else {
                                // Last resort - try lowercase "root"
                                foundRoot = findEntityDeep(named: "root", in: entity)
                                if foundRoot != nil {
                                    print("🔍 Found lowercase 'root' entity")
                                    addLog("🔍 Found lowercase 'root' entity")
                                }
                            }
                        }
                        
                        if let foundRoot = foundRoot, isEntityInScene(foundRoot) {
                            // Save for future use
                            self.rootEntity = foundRoot
                            
                            // Send notification with found Root entity
                            NotificationCenter.default.post(
                                name: NSNotification.Name("RealityKit.NotificationTrigger"),
                                object: nil,
                                userInfo: [
                                    "RealityKit.NotificationTrigger.Scene": scene,
                                    "RealityKit.NotificationTrigger.Entity": foundRoot,
                                    "RealityKit.NotificationTrigger.Identifier": "loop"
                                ]
                            )
                            
                            print("📬 Posted notification with newly found Root entity")
                            addLog("📬 Posted notification with newly found Root")
                        } else {
                            // Last resort - scene-only notification
                            print("⚠️ Could not find Root entity for notification")
                            addLog("⚠️ Using scene-only notification (no Root)")
                            
                            NotificationCenter.default.post(
                                name: NSNotification.Name("RealityKit.NotificationTrigger"),
                                object: nil,
                                userInfo: [
                                    "RealityKit.NotificationTrigger.Scene": scene,
                                    "RealityKit.NotificationTrigger.Identifier": "loop"
                                ]
                            )
                            
                            print("📬 Posted scene-only notification as fallback")
                            addLog("📬 Posted scene-only notification")
                        }
                    } else {
                        // Scene-only notification as last fallback
                        print("⚠️ No space entity available for Root search")
                        addLog("⚠️ No space entity available")
                        
                        NotificationCenter.default.post(
                            name: NSNotification.Name("RealityKit.NotificationTrigger"),
                            object: nil,
                            userInfo: [
                                "RealityKit.NotificationTrigger.Scene": scene,
                                "RealityKit.NotificationTrigger.Identifier": "loop"
                            ]
                        )
                        
                        print("📬 Posted scene-only notification (no space entity)")
                        addLog("📬 Posted scene-only notification")
                    }
                }
                
                // Set flag regardless of which notification approach was used
                print("✅ Notification posted. Setting flag for ID \(currentNewId).")
                addLog("✅ Notification posted with identifier 'loop'")
                self.notificationSentForEntityID = currentNewId
                
                // Check state after a delay
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled, let rootEntity = self.rootEntity {
                        let message = "🔍 Post-notification check: Root entity state: isEnabled=\(rootEntity.isEnabled)"
                        print(message)
                        addLog(message)
                    }
                } catch {
                    // Ignore errors in post-check
                }
            }
        }
    }
    
    // MARK: - Scene Setup Helpers
    
    private func getSpaceForScene(for entityID: Entity.ID) -> SpaceData? {
        if let currentSpace = selectedSpace, entityWrapper.getSpaceEntity()?.id == entityID {
            return currentSpace
        }
        if let appModelSpace = appModel.selectedSpace, entityWrapper.getSpaceEntity()?.name == appModelSpace.spaceName {
            print("   - getSpaceForScene: Using appModel space based on name match.")
            return appModelSpace
        }
        if let currentSpace = selectedSpace, currentSpace.spaceName == entityWrapper.getSpaceEntity()?.name {
            print("   - getSpaceForScene: Falling back to selectedSpace based on name match.")
            return currentSpace
        }
        print("⚠️ getSpaceForScene: Could not find matching SpaceData for entity ID \(entityID) and selectedSpace '\(selectedSpace?.spaceName ?? "nil")'")
        return nil
    }
    
    // MARK: - Entity Helpers
    
    /// Helper to find an entity by name recursively through the hierarchy
    private func findEntityDeep(named name: String, in parent: Entity) -> Entity? {
        if parent.name == name {
            return parent
        }
        
        for child in parent.children {
            if let found = findEntityDeep(named: name, in: child) {
                return found
            }
        }
        
        return nil
    }
    
    /// Helper to verify if an entity is actually connected to a scene
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
    
    // Function to manually trigger a notification for debugging
    private func triggerManualNotification() {
        guard let scene = realityKitScene else {
            print("❌ No RealityKit scene available from environment")
            addLog("❌ Manual notification failed: No scene")
            return
        }
        
        // Try to use our cached Root entity
        if let root = rootEntity, isEntityInScene(root) {
            addLog("🔔 Manual notification with Root entity")
            
            NotificationCenter.default.post(
                name: NSNotification.Name("RealityKit.NotificationTrigger"),
                object: nil,
                userInfo: [
                    "RealityKit.NotificationTrigger.Scene": scene,
                    "RealityKit.NotificationTrigger.Entity": root,
                    "RealityKit.NotificationTrigger.Identifier": "loop"
                ]
            )
        } else {
            addLog("🔔 Manual notification (scene only)")
            
            NotificationCenter.default.post(
                name: NSNotification.Name("RealityKit.NotificationTrigger"),
                object: nil,
                userInfo: [
                    "RealityKit.NotificationTrigger.Scene": scene,
                    "RealityKit.NotificationTrigger.Identifier": "loop"
                ]
            )
        }
        
        print("🔄 Manual notification 'loop' sent")
    }
    
    private func openWindowsIfNeeded() {
        openWindow(id: "spaceNavBar")
        openWindow(id: "spaceMap")
    }
    
    // MARK: - Debug Overlay
    
    private var debugOverlay: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    let currentEntity = entityWrapper.getSpaceEntity()
                    let currentEntityID = currentEntity?.id
                    Text("Wrapper SpaceEnt: \(currentEntity?.name ?? "None") (ID: \(currentEntityID?.description ?? "N/A"))")
                        .foregroundColor(currentEntity != nil ? .green : .red)
                    Text("Selected Space: \(selectedSpace?.spaceName ?? "None")")
                    Text("Root Entity: \(rootEntity != nil ? "Found ✅" : "Not Found ❌")")
                        .foregroundColor(rootEntity != nil ? .green : .red)
                    
                    Divider().background(.gray)
                    
                    Text("Notif Sent For ID: \(notificationSentForEntityID?.description ?? "nil")")
                         .foregroundColor(notificationSentForEntityID == currentEntityID && currentEntity != nil ? .blue : .orange)
                    Text("Notif Task Active: \(notificationPostTask != nil && !notificationPostTask!.isCancelled ? "Yes" : "No")")
                        .foregroundColor(notificationPostTask != nil && !notificationPostTask!.isCancelled ? .yellow : .gray)
                    
                    Divider().background(.gray)
                    
                    Text("Loading State: \(isLoading ? "Loading" : "Idle")")
                        .foregroundColor(isLoading ? .yellow : .green)
                    if let errorMessage {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(.pink)
                            .lineLimit(2)
                    }
                    
                    Divider().background(.gray)
                    
                    Text("Anchor Children: \(anchorEntity.children.count)")
                    Text("RV Update Cntr: \(realityViewUpdateCounter)")
                    
                    // Notification log display
                    Divider().background(.gray)
                    Text("Notification Log:")
                        .fontWeight(.bold)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(notificationLogs.enumerated()), id: \.offset) { index, log in
                                Text(log)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(height: 100)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(5)
                }
                .font(.system(size: 10))
                .padding(8)
                .background(Color.black.opacity(0.75))
                .cornerRadius(8)
                .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                VStack(spacing: 8) {
                    Button(action: triggerManualNotification) {
                                            Image(systemName: "bell.fill")
                                                .font(.system(size: 16))
                                                .padding(8)
                                                .background(Color.blue.opacity(0.75))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
                                        }
                                        .help("Send manual notification")
                                        
                                        Button(action: refreshSpace) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 16))
                                                .padding(8)
                                                .background(Color.black.opacity(0.75))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
                                        }
                                        .help("Refresh space")
                                        
                                        Button(action: {
                                            notificationLogs.removeAll()
                                            addLog("🧹 Log cleared")
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 16))
                                                .padding(8)
                                                .background(Color.red.opacity(0.75))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
                                        }
                                        .help("Clear logs")
                                    }
                                }
                                Spacer()
                            }
                            .padding()
                            .zIndex(10)
                        }
                        
                        private func refreshSpace() {
                            print("🔄 Manual refresh triggered")
                            addLog("🔄 Manual refresh triggered")
                            cancellables.forEach { $0.cancel() }
                            cancellables.removeAll()
                            notificationPostTask?.cancel()
                            notificationPostTask = nil
                            errorMessage = nil
                            initializeSpace()
                        }
                    }
