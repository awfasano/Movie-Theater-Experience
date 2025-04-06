import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        VideoSyncService.shared.handleAppTermination()
    }
}

@main
struct Movie_Theater_ExperienceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var appModel = AppModel()
    @StateObject private var immersiveSpaceManager = ImmersiveSpaceManager.shared
    @StateObject private var selectedSpace = SelectedSpace()
    @StateObject private var spaceManager = ImmersiveSpaceManager.shared
    @StateObject private var sharedSelection = SharedSeatSelection.shared
    @StateObject private var theatreEntityWrapper = TheatreEntityWrapper.shared
    @StateObject private var windowManager = WindowManager()
    
    // Inject the modular managers.
    @StateObject private var firebaseEventManager = FirebaseEventManager.shared
    @StateObject private var emojiManager = EmojiManager.shared
    
    // Space related managers
    @StateObject private var spacesChatManager = SpacesChatManager.shared
    
    @Environment(\.openWindow) var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("userId") var userId: String = ""
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(selectedSpace)
                .environmentObject(firebaseEventManager) // Injected for movie experience
        }
        
        // Volumetric preview window - using selectedSpace.
        WindowGroup("Volume", id: "volume") {
            if let spaceData = selectedSpace.space {
                VolumetricSpaceWrapper(space: spaceData)
                    .environment(appModel)
                    .environmentObject(selectedSpace)
                    .environmentObject(spaceManager)
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
                .environmentObject(selectedSpace)
                .environmentObject(spaceManager)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .environmentObject(windowManager)
                .onAppear {
                    if userId.isEmpty {
                        userId = UUID().uuidString
                        print("Main App: Generated new userId: \(userId)")
                    } else {
                        print("Main App: Existing userId: \(userId)")
                    }
                }
        }
        .defaultSize(width: 1000, height: 600)
        
        // Immersive space window for movie experience.
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            if #available(visionOS 1.0, *) {
                ImmersiveView()
                    .environment(appModel)
                    .environmentObject(spaceManager)
                    .environmentObject(sharedSelection)
                    .environmentObject(theatreEntityWrapper)
                    .environmentObject(windowManager)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
        
        // Immersive space window for Spaces.
        ImmersiveSpace(id: appModel.spacesID) {
            if #available(visionOS 1.0, *) {
                SpacesView()
                    .environment(appModel)
                    .environmentObject(selectedSpace)
                    .environmentObject(spaceManager)
                    .environmentObject(sharedSelection)
                    .environmentObject(windowManager)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
        
        // Other windows remain unchanged...
        WindowGroup("Seat Map", id: "seatMap") {
            SeatMapView()
                .environment(appModel)
                .environmentObject(spaceManager)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.seatMap)
                }
        }
        
        
        // Add to your Movie_Theater_ExperienceApp scene declaration
        WindowGroup("Space Map", id: "spaceMap") {
            SpaceMapView()
                .environment(appModel)
                .environmentObject(selectedSpace)
                .environmentObject(spaceManager)
                .environmentObject(windowManager)
                .onDisappear {
                    //windowManager.windowClosed(.spaceMap)
                }
        }
        .defaultSize(width: 1024, height: 1300)
        .windowStyle(.plain)
        // Inside your Movie_Theater_ExperienceApp's body, add a new WindowGroup:

        WindowGroup("Space Nav Bar", id: "spaceNavBar") {
            SpacesNavBarView()
                .environment(appModel)
                .environmentObject(spaceManager)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.navBar)
                }
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 50)
        
        // Space Chat Window
        WindowGroup(id: "spaceChatWindow") {
            SpacesChatWindow()
                .environment(appModel)
                .environmentObject(selectedSpace)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.chat)
                }
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)
        
        // Space Emoji Window
        WindowGroup(id: "spaceEmojiWindow") {
            SpacesEmojiWindow()
                .environment(appModel)
                .environmentObject(selectedSpace)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.emoji)
                }
        }
        .defaultSize(width: 300, height: 180)
        .windowStyle(.plain)
        
        WindowGroup("Chat Settings", id: "chatSettings") {
            ChatSettingsNavBar()
                .environment(appModel)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.chatSettings)
                }
        }
        .defaultSize(width: 350, height: 225)
        
        WindowGroup("Emoji Window", id: "emojiWindow") {
            if let event = appModel.currentEvent {
                EmojiButtonView(eventId: event.id ?? "", date: event.date)
                    .environmentObject(emojiManager) // Inject EmojiManager for emoji view.
                    .background(Color.clear)
                    .onDisappear {
                        windowManager.windowClosed(.emoji)
                    }
            }
        }
        .defaultSize(width: 300, height: 100)
        .windowStyle(.plain)
        
        WindowGroup(id: "chatWindow") {
            if let event = appModel.currentEvent {
                ChatView(viewModel: ChatViewModel(
                    eventId: event.id ?? "",
                    date: event.date,
                    eventManager: firebaseEventManager  // Inject the configured event manager.
                ))
                .onDisappear {
                    windowManager.windowClosed(.chat)
                }
            }
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)
        
        WindowGroup("Nav Bar", id: "navBar") {
            NavBarView()
                .environment(appModel)
                .environmentObject(spaceManager)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.navBar)
                }
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 50)
        
        WindowGroup("Movie Window", id: "movieWindow") {
            MovieWindow()
                .environment(appModel)
                .environmentObject(spaceManager)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.movie)
                }
        }
        .defaultSize(width: 600, height: 1500)
        .windowStyle(.plain)
        
        WindowGroup(id: "exitingWindow", for: WatchStats.self) { stats in
            if let unwrappedStats = stats.wrappedValue {
                ExitingWindow(stats: unwrappedStats)
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
