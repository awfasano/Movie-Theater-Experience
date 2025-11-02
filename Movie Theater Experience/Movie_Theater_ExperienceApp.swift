@main
struct Movie_Theater_ExperienceApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var immersiveSpaceManager = ImmersiveSpaceManager.shared
    @StateObject private var sharedSpaceSeatSelection = SharedSpaceSeatSelection()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSpaceSeatSelection)
        }
        
        // Window for volumetric space preview
        WindowGroup("Volume", id: "volume", for: String.self) { spaceId in
            if let spaceId = spaceId, let selectedSpace = SpaceService.shared.spaces.first(where: { $0.id == spaceId }) {
                VolumetricSpaceView(space: selectedSpace, onEnter: {
                    Task {
                        do {
                            try await openImmersiveSpace(id: appModel.spacesID)
                            print("✅ Immersive space opened successfully")
                        } catch {
                            print("❌ Failed to open immersive space: \(error)")
                        }
                    }
                })
                    .environment(appModel)
                    .environmentObject(immersiveSpaceManager)
                    .environmentObject(sharedSpaceSeatSelection)
            } else {
                Text("No space selected or invalid space ID")
            }
        }
        
        // Window for spaces view
        WindowGroup("Spaces", id: "spacesWindow") {
            SpacesView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSpaceSeatSelection)
                .environmentObject(appModel.drawingViewModel)
        }
        
        // Immersive spaces
        
        
        ImmersiveSpace(id: appModel.spacesID) {
            SpacesView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSpaceSeatSelection)
                .environmentObject(appModel.drawingViewModel)
        }
        
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSpaceSeatSelection)
        }
    }
} 
