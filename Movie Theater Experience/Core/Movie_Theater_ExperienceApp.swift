import SwiftUI
import FirebaseCore

// AppDelegate for Firebase initialization
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let startTime = Date()
        print("🔥 [Firebase] Starting configuration...")

        // Configure Firebase synchronously but with disabled services for faster startup
        FirebaseApp.configure()

        let duration = Date().timeIntervalSince(startTime)
        print("✅ [Firebase] Configured in \(String(format: "%.2f", duration))s")

        return true
    }
}

@main
struct Movie_Theater_ExperienceApp: App {
    // Firebase AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // AppModel: Holds shared state including userId
    @State private var appModel = AppModel.shared

    // AppStorage for persisting userId
    @AppStorage("userId") var appStorageUserId: String = ""
    @StateObject private var selectedSpace = SelectedSpace()

    // Other managers and wrappers
    @StateObject private var immersiveSpaceManager = ImmersiveSpaceManager.shared
    @StateObject private var sharedSelection = SharedSeatSelection.shared
    @StateObject private var windowManager = WindowManager()
    @StateObject private var spacesEntityWrapper = SpacesEntityWrapper.shared
    @StateObject private var firebaseEventManager = FirebaseEventManager.shared
    @StateObject private var spacesChatManager = SpacesChatManager.shared
    @StateObject private var sharePlayManager = SharePlayManager.shared

    // Hosted Events managers
    @StateObject private var hostedEventManager = HostedEventManager.shared
    @StateObject private var personaManager = PersonaTableManager()
    @StateObject private var triviaGameManager = TriviaGameManager.shared
    @StateObject private var triviaImmersiveManager = TriviaImmersiveManager()
    
    // REMOVED: triviaSharePlayManager
    
    // Activity Identifiers for Spaces (not trivia)
    let publicSpaceActivityIdentifier = "com.yourcompany.yourapp.PublicSpaceActivity"
    let directCallActivityIdentifier = "com.yourcompany.yourapp.DirectCallActivity"

    // AppStorage properties
    @AppStorage("userID") private var userID: String = ""
    @AppStorage("username") private var username: String = ""
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        
        WindowGroup(id: WindowType.mainContent.rawValue) {
            TabBarWindow()
                .environment(appModel)
                .trackWindow(type: .mainContent)
                .environmentObject(windowManager)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSelection)
                .environmentObject(selectedSpace)
                .environmentObject(firebaseEventManager)
                .environmentObject(hostedEventManager)
                .environmentObject(personaManager)
                .environmentObject(triviaGameManager)
                .environmentObject(triviaImmersiveManager)
                // REMOVED: triviaSharePlayManager
                .onAppear {
                    HostedEventManager.shared.setPersonaManager(personaManager)
                }
        }
        .defaultSize(width: 1000, height: 600)
        
        
        WindowGroup("Firebase Debug", id: "firebaseDebug") {
            FirebaseDebugView()
                .environmentObject(hostedEventManager)
                .environmentObject(triviaGameManager)
                .environmentObject(triviaImmersiveManager)
        }
        .defaultSize(width: 600, height: 800)
        
        // Volumetric preview window
        WindowGroup("Volume", id: "volume") {
            Group {
                if let spaceData = appModel.selectedSpace {
                    VolumetricSpaceWrapper(space: spaceData)
                        .environment(appModel)
                        .environmentObject(ImmersiveSpaceManager.shared)
                        .environmentObject(sharedSelection)
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
            .environmentObject(windowManager)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.5, height: 0.5, depth: 1, in: .meters)
                
        // User List Window
        WindowGroup(id: WindowType.userListWindow.rawValue) {
            UserListView()
                .environment(appModel)
                .trackWindow(type: .userListWindow)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 500, height: 600)
        .windowStyle(.plain)
        
        // Immersive space window for Spaces
        ImmersiveSpace(id: appModel.spacesID) {
            SpacesView()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .environmentObject(spacesEntityWrapper)
                .environmentObject(windowManager)
        }
        .handlesExternalEvents(
            matching: [publicSpaceActivityIdentifier, directCallActivityIdentifier]
        )
        .immersionStyle(selection: .constant(.full), in: .full)

        // UPDATED: ImmersiveSpace for Trivia (SharePlay removed)
        ImmersiveSpace(id: "TriviaSpace") {
            TriviaSpaceView()
                .environmentObject(hostedEventManager)
                .environmentObject(personaManager)
                .environmentObject(triviaGameManager)
                .environmentObject(triviaImmersiveManager)
                // REMOVED: triviaSharePlayManager and task block
        }
        
        // Audio Controls window
        WindowGroup("Audio Controls", id: WindowType.audioControls.rawValue) {
            VolumeControlView()
                .background(.clear)
                .environment(appModel)
                .environmentObject(spacesEntityWrapper)
                .trackWindow(type: .audioControls)
                .environmentObject(windowManager)
        }
        .windowStyle(.plain)
        .defaultSize(width: 360, height: 420)
        .windowResizability(.contentSize)
        
        // Space Map window
        WindowGroup("Space Map", id: WindowType.spaceMap.rawValue) {
            SpaceMapView()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .trackWindow(type: .spaceMap)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 800, height: 750)
        .windowStyle(.plain)
        
        // Space Nav Bar window
        WindowGroup("Space Nav Bar", id: WindowType.spaceNavBar.rawValue) {
            SpacesNavBarView()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .environmentObject(sharedSelection)
                .environmentObject(spacesEntityWrapper)
                .trackWindow(type: .spaceNavBar)
                .environmentObject(windowManager)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1200, height: 25)
        
        // Space Chat window
        WindowGroup(id: WindowType.spaceChatWindow.rawValue) {
            SpacesChatWindow()
                .environment(appModel)
                .trackWindow(type: .spaceChatWindow)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)
        
        // Space Emoji window
        WindowGroup(id: WindowType.spaceEmojiWindow.rawValue) {
            SpacesEmojiWindow()
                .environment(appModel)
                .trackWindow(type: .spaceEmojiWindow)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 300, height: 180)
        .windowStyle(.plain)
        
        // Chat Settings window
        WindowGroup("Chat Settings", id: WindowType.chatSettings.rawValue) {
            ChatSettingsNavBar()
                .environment(appModel)
                .trackWindow(type: .chatSettings)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 350, height: 225)
        
        // Chat window for Movie Theatre
        WindowGroup(id: WindowType.chat.rawValue) {
            Group {
                if let event = appModel.currentEvent {
                    ChatView(viewModel: ChatViewModel(
                        eventId: event.id ?? "",
                        date: event.date,
                        eventManager: firebaseEventManager
                    ))
                    .environment(appModel)
                    // REMOVED: triviaSharePlayManager
                } else {
                    EmptyView()
                }
            }
            .trackWindow(type: .chat)
            .environmentObject(windowManager)
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)
        
        WindowGroup("Storyteller", id: WindowType.storytellerWindow.rawValue) {
            StoriesListView()
                .environment(appModel)
                .trackWindow(type: .storytellerWindow)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 1250, height: 800)
        .windowStyle(.plain)
        
        // Movement Control
        WindowGroup(id: WindowType.movementControl.rawValue) {
            MovementControlView()
                .environment(appModel)
                .trackWindow(type: .movementControl)
                .environmentObject(windowManager)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.4, height: 0.4, depth: 0.4, in: .meters)
        
        // Browser Windows
        WindowGroup("Web Browser 1", id: "webBrowser_1") {
            WebBrowserView()
                .onAppear {
                    windowManager.trackBrowserWindow("1")
                }
                .onDisappear {
                    windowManager.untrackBrowserWindow("1")
                }
                .environmentObject(windowManager)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.plain)

        WindowGroup("Web Browser 2", id: "webBrowser_2") {
            WebBrowserView()
                .onAppear {
                    windowManager.trackBrowserWindow("2")
                }
                .onDisappear {
                    windowManager.untrackBrowserWindow("2")
                }
                .environmentObject(windowManager)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.plain)

        WindowGroup("Web Browser 3", id: "webBrowser_3") {
            WebBrowserView()
                .onAppear {
                    windowManager.trackBrowserWindow("3")
                }
                .onDisappear {
                    windowManager.untrackBrowserWindow("3")
                }
                .environmentObject(windowManager)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.plain)

        WindowGroup("Web Browser 4", id: "webBrowser_4") {
            WebBrowserView()
                .onAppear {
                    windowManager.trackBrowserWindow("4")
                }
                .onDisappear {
                    windowManager.untrackBrowserWindow("4")
                }
                .environmentObject(windowManager)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.plain)

        WindowGroup("Web Browser 5", id: "webBrowser_5") {
            WebBrowserView()
                .onAppear {
                    windowManager.trackBrowserWindow("5")
                }
                .onDisappear {
                    windowManager.untrackBrowserWindow("5")
                }
                .environmentObject(windowManager)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.plain)
        
        // Host Controls Window
        WindowGroup("Host Controls", id: "hostControls") {
            TriviaHostControlsView()
                .environmentObject(hostedEventManager)
                .environmentObject(triviaGameManager)
                .environmentObject(triviaImmersiveManager)
                // REMOVED: triviaSharePlayManager
        }
        .defaultSize(width: 1000, height: 800)
        
        // REMOVED: SharePlay Debug Window entirely
        
        // Exiting window
        WindowGroup(id: WindowType.exitingWindow.rawValue, for: WatchStats.self) { stats in
            Group {
                if let unwrappedStats = stats.wrappedValue {
                    ExitingWindow(stats: unwrappedStats)
                        .environment(appModel)
                } else {
                    EmptyView()
                }
            }
            .trackWindow(type: .exitingWindow)
            .environmentObject(windowManager)
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
