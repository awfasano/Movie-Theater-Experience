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
        WindowGroup("Volume", id: "volume") {
            if let selectedSpace = appModel.selectedSpace {
                VolumetricSpaceView(space: selectedSpace)
                    .environment(appModel)
                    .environmentObject(immersiveSpaceManager)
                    .environmentObject(sharedSpaceSeatSelection)
            } else {
                Text("No space selected")
            }
        }
        
        // Window for spaces view
        WindowGroup("Spaces", id: "spacesWindow") {
            SpacesView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSpaceSeatSelection)
        }
        
        // Immersive spaces
        ImmersiveSpace(id: appModel.spacesID) {
            SpacesView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSpaceSeatSelection)
        }
        
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSpaceSeatSelection)
        }
    }
} 