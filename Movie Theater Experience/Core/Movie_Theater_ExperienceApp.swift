import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }

}

@main
struct Movie_Theater_ExperienceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // Create the AppModel which holds your shared state including the selected space.
    @State private var appModel = AppModel()
    
    // Other managers and wrappers remain as before.
    @StateObject private var immersiveSpaceManager = ImmersiveSpaceManager.shared
    @StateObject private var spaceManager = ImmersiveSpaceManager.shared
    @StateObject private var sharedSelection = SharedSeatSelection.shared
    @StateObject private var theatreEntityWrapper = TheatreEntityWrapper.shared
    @StateObject private var windowManager = WindowManager()
    @StateObject private var spacesEntityWrapper = SpacesEntityWrapper.shared

    @StateObject private var audioLoader = SpatialAudioLoader()

    // Inject additional managers.
    @StateObject private var firebaseEventManager = FirebaseEventManager.shared
    @StateObject private var emojiManager = EmojiManager.shared
    
    // Space-related managers.
    @StateObject private var spacesChatManager = SpacesChatManager.shared
    
    @Environment(\.openWindow) var openWindow
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("userId") var userId: String = ""
    
    var body: some Scene {
        // Main content window.
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(firebaseEventManager) // For movie experience.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Task { await VideoSyncService.shared.cleanup(level: .full) }
                    }
                }
        }
        
        // Volumetric preview window - using appModel.selectedSpace.
        WindowGroup("Volume", id: "volume") {
            if let spaceData = appModel.selectedSpace {
                VolumetricSpaceWrapper(space: spaceData)
                    .environment(appModel)
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
                // SpacesView should now be updated to use appModel.selectedSpace internally.
                SpacesView(audioLoader: audioLoader)
                    .environment(appModel)
                    .environmentObject(spaceManager)
                    .environmentObject(spacesEntityWrapper)
                    .environmentObject(windowManager)
                
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
        
        WindowGroup("Audio Controls", id: "audioControls") {
          // make sure we actually have a selected space + entity
          if let space  = appModel.selectedSpace,
             let entity = spacesEntityWrapper.getSpaceEntity() {
            VolumeControlView(
              audioLoader:  audioLoader,
              spaceEntity:  entity,
              spaceMeta:    space
            )
            .environmentObject(appModel)
            .environmentObject(spacesEntityWrapper)
            .background(.clear) // ensure clear background
          } else {
            Text("No space loaded")
              .padding()
          }
        }
        .windowStyle(.plain) // 🔥 removes system material + borders
        .defaultSize(width: 360, height: 420) // 👈 starting size
        .windowResizability(.contentSize)
        
        
        // Space Map window.
        WindowGroup("Space Map", id: "spaceMap") {
            // SpaceMapView now uses appModel.selectedSpace rather than a separate SelectedSpace.
            SpaceMapView()
                .environment(appModel)
                .environmentObject(spaceManager)
                .environmentObject(windowManager)
                .onDisappear {
                    // Optionally call any cleanup here.
                }
        }
        .defaultSize(width: 1600, height: 1300)
        .windowStyle(.plain)
        
        // Space Nav Bar window.
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
        
        // Space Chat window.
        WindowGroup(id: "spaceChatWindow") {
            SpacesChatWindow()
                .environment(appModel)
                .environmentObject(windowManager)
                .onDisappear {
                    windowManager.windowClosed(.chat)
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
                    windowManager.windowClosed(.emoji)
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
        
        // Emoji window.
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
        
        // Chat window.
        WindowGroup(id: "chatWindow") {
            if let event = appModel.currentEvent {
                ChatView(viewModel: ChatViewModel(
                    eventId: event.id ?? "",
                    date: event.date,
                    eventManager: firebaseEventManager
                ))
                .onDisappear {
                    windowManager.windowClosed(.chat)
                }
            }
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)
        
        // Nav Bar window.
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
        
        // Movie window.
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
        
        // Exiting window.
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
