import SwiftUI
import FirebaseCore // Required for AppDelegate

// AppDelegate for Firebase initialization
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        print("🔥 Firebase configured via AppDelegate.")
        return true
    }
}

@main
struct Movie_Theater_ExperienceApp: App {
    // Firebase AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // AppModel: Holds shared state including userId
    @State private var appModel = AppModel() // Using a new instance, not AppModel.shared directly as @State
                                          // If AppModel.shared is intended, ensure it's properly managed.
                                          // For this example, a new @State instance is fine.

    // AppStorage for persisting userId
    // The key "userId" here must match the key you intend to use for persistence.
    @AppStorage("userId") var appStorageUserId: String = ""

    // Other managers and wrappers
    // Using .shared for these implies they are singletons.
    // If they are @ObservableObject, @StateObject is appropriate if they are created here.
    // If they are @Observable, direct use or @State is fine.
    @StateObject private var immersiveSpaceManager = ImmersiveSpaceManager.shared
    // @StateObject private var spaceManager = ImmersiveSpaceManager.shared // Duplicate of immersiveSpaceManager?
    @StateObject private var sharedSelection = SharedSeatSelection.shared
    @StateObject private var theatreEntityWrapper = TheatreEntityWrapper.shared
    @StateObject private var windowManager = WindowManager() // Assuming WindowManager is an ObservableObject
    @StateObject private var spacesEntityWrapper = SpacesEntityWrapper.shared
    @StateObject private var audioLoader = SpatialAudioLoader()
    @StateObject private var firebaseEventManager = FirebaseEventManager.shared
    @StateObject private var emojiManager = EmojiManager.shared
    @StateObject private var spacesChatManager = SpacesChatManager.shared

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        // Main content window.
        WindowGroup {
            ContentView()
                .environment(appModel) // Pass the AppModel instance
                .environmentObject(immersiveSpaceManager)
                .environmentObject(firebaseEventManager)
                .environmentObject(windowManager) // Ensure WindowManager is available if ContentView needs it
                .onAppear {
                    // Initialize userId when the main ContentView appears.
                    // This is the earliest reliable point in the UI lifecycle.
                    print("🚀 [App] ContentView appeared. Initializing userId in AppModel.")
                    appModel.initializeUserId(from: appStorageUserId, appStorage: _appStorageUserId)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Task {
                            print("Backgrounding: Cleaning up VideoSyncService.")
                            await VideoSyncService.shared.cleanup(level: .full)
                        }
                    }
                }
        }
        
        // Volumetric preview window - using appModel.selectedSpace.
        WindowGroup("Volume", id: "volume") {
            if let spaceData = appModel.selectedSpace {
                VolumetricSpaceWrapper(space: spaceData)
                    .environment(appModel)
                    .environmentObject(ImmersiveSpaceManager.shared) // Use .shared directly or pass the instance
                    .environmentObject(sharedSelection)
                    .environmentObject(theatreEntityWrapper)
                    .environmentObject(windowManager)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No space selected")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Select a space from the Spaces browser")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 600, height: 350)
        
        // Main Tab Bar window.
        WindowGroup("Tab Bar", id: "tabBar") {
            TabBarWindow()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .environmentObject(windowManager)
                // Removed initializeUserId from here as it's now in ContentView's onAppear
        }
        .defaultSize(width: 1000, height: 600)
        
        // Immersive space window for movie experience.
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            // No need for #available check if your app's minimum target is visionOS 1.0+
            ImmersiveView()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .environmentObject(windowManager)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
        
        // Immersive space window for Spaces.
        ImmersiveSpace(id: appModel.spacesID) {
            SpacesView(audioLoader: audioLoader)
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .environmentObject(spacesEntityWrapper)
                .environmentObject(windowManager)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
        
        WindowGroup("Audio Controls", id: "audioControls") {
            if let space = appModel.selectedSpace,
               let entity = spacesEntityWrapper.getSpaceEntity() {
                VolumeControlView(
                    audioLoader: audioLoader,
                    spaceEntity: entity,
                    spaceMeta: space
                )
                .environment(appModel) // Pass appModel if needed
                .environmentObject(spacesEntityWrapper)
                .background(.clear)
            } else {
                Text("No space loaded")
                    .padding()
            }
        }
        .windowStyle(.plain)
        .defaultSize(width: 360, height: 420)
        .windowResizability(.contentSize)
        
        // Space Map window.
        WindowGroup("Space Map", id: "spaceMap") {
            SpaceMapView()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.seatMap) // Assuming .seatMap corresponds to "spaceMap"
                }
        }
        .defaultSize(width: 1600, height: 1300)
        .windowStyle(.plain)
        
        // Space Nav Bar window.
        WindowGroup("Space Nav Bar", id: "spaceNavBar") {
            SpacesNavBarView()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper) // This might be specific to movie theatre, check if needed for SpacesNavBar
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.navBar) // Assuming .navBar corresponds to "spaceNavBar"
                }
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 50)
        
        // Space Chat window.
        WindowGroup(id: "spaceChatWindow") {
            SpacesChatWindow()
                .environment(appModel)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.chat) // Assuming .chat corresponds to "spaceChatWindow"
                }
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)
        
        // Space Emoji window.
        WindowGroup(id: "spaceEmojiWindow") {
            SpacesEmojiWindow()
                .environment(appModel)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.emoji) // Assuming .emoji corresponds to "spaceEmojiWindow"
                }
        }
        .defaultSize(width: 300, height: 180)
        .windowStyle(.plain)
        
        // Chat Settings window.
        WindowGroup("Chat Settings", id: "chatSettings") {
            ChatSettingsNavBar()
                .environment(appModel)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.chatSettings)
                }
        }
        .defaultSize(width: 350, height: 225)
        
        // Emoji window for Movie Theatre.
        WindowGroup("Emoji Window", id: "emojiWindow") {
            if let event = appModel.currentEvent {
                EmojiButtonView(eventId: event.id ?? "", date: event.date)
                    .environmentObject(emojiManager)
                    .background(Color.clear)
                    .onDisappear {
                        windowManager.windowClosed(.emoji)
                    }
            }
        }
        .defaultSize(width: 300, height: 100)
        .windowStyle(.plain)
        
        // Chat window for Movie Theatre.
        WindowGroup(id: "chatWindow") {
            if let event = appModel.currentEvent {
                ChatView(viewModel: ChatViewModel(
                    eventId: event.id ?? "",
                    date: event.date,
                    eventManager: firebaseEventManager
                ))
                .environment(appModel) // Pass appModel if ChatView needs it
                .onDisappear {
                    windowManager.windowClosed(.chat)
                }
            }
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)
        
        // Nav Bar window for Movie Theatre.
        WindowGroup("Nav Bar", id: "navBar") {
            NavBarView()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.navBar)
                }
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 50)
        
        // Movie window.
        WindowGroup("Movie Window", id: "movieWindow") {
            MovieWindow()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared) // Pass if MovieWindow needs it
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.movie)
                }
        }
        .defaultSize(width: 600, height: 1500) // Height seems large, adjust if needed
        .windowStyle(.plain)
        
        // Exiting window.
        WindowGroup(id: "exitingWindow", for: WatchStats.self) { stats in
            if let unwrappedStats = stats.wrappedValue {
                ExitingWindow(stats: unwrappedStats)
                    .environment(appModel) // Pass appModel if needed
                    .onDisappear {
                        windowManager.windowClosed(.exitingWindow)
                    }
            }
        }
        .defaultSize(width: 600, height: 800)
        .windowStyle(.plain)
    }
}

extension Movie_Theater_ExperienceApp {
    func openSpaceList() {
        openWindow(id: "spaceList")
    }
}
