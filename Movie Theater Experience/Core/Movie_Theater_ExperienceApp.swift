import SwiftUI
import FirebaseCore // Required for AppDelegate
import GroupActivities // Required for SharePlay functionality

// AppDelegate for Firebase initialization
class AppDelegate: NSObject, UIApplicationDelegate {
    // Using regular spaces
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
    // Assuming AppModel is @Observable (SwiftUI 5+)
    @State private var appModel = AppModel.shared

    // AppStorage for persisting userId
    @AppStorage("userId") var appStorageUserId: String = ""
    @StateObject private var selectedSpace = SelectedSpace()

    // Other managers and wrappers
    @StateObject private var immersiveSpaceManager = ImmersiveSpaceManager.shared
    @StateObject private var sharedSelection = SharedSeatSelection.shared
    // Initialize WindowManager here so it's available for injection
    @StateObject private var windowManager = WindowManager()
    @StateObject private var spacesEntityWrapper = SpacesEntityWrapper.shared
    @StateObject private var firebaseEventManager = FirebaseEventManager.shared
    @StateObject private var spacesChatManager = SpacesChatManager.shared
    @StateObject private var sharePlayManager = SharePlayManager.shared

    // Added Hosted Events managers
    @StateObject private var hostedEventManager = HostedEventManager.shared
    @StateObject private var personaManager = PersonaTableManager()
    @StateObject private var triviaGameManager = TriviaGameManager.shared
    
    // ADDED: SharePlay manager for trivia
    @StateObject private var triviaSharePlayManager = TriviaSharePlayManager.shared
    
    // Activity Identifiers (Ensure these match your Info.plist if using GroupActivities)
    // Assuming PublicSpaceActivity and DirectCallActivity might be defined elsewhere, otherwise use the strings.
    let publicSpaceActivityIdentifier = "com.yourcompany.yourapp.PublicSpaceActivity"
    let directCallActivityIdentifier = "com.yourcompany.yourapp.DirectCallActivity"

    // AppStorage properties for persisting the stable userID and the user's display name.
    @AppStorage("userID") private var userID: String = ""
    @AppStorage("username") private var username: String = ""
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        
        WindowGroup(id: WindowType.mainContent.rawValue) {
            TabBarWindow()
                // Inject all dependencies for the entire window's view hierarchy
                .environment(appModel)
                .trackWindow(type: .mainContent)
                .environmentObject(windowManager)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSelection)
                .environmentObject(selectedSpace)
                .environmentObject(firebaseEventManager)
                // Apply the tracker to this main window
                .environmentObject(hostedEventManager)
                .environmentObject(personaManager)
                .environmentObject(triviaGameManager)
                .environmentObject(triviaSharePlayManager) // ADDED
                .onAppear {
                    HostedEventManager.shared.setPersonaManager(personaManager)
                }
        }
        .defaultSize(width: 1000, height: 600)
        
        
        WindowGroup("Firebase Debug", id: "firebaseDebug") {
            FirebaseDebugView()
                .environmentObject(hostedEventManager)
                .environmentObject(triviaGameManager)
        }
        .defaultSize(width: 600, height: 800)
        
        // Volumetric preview window
        WindowGroup("Volume", id: "volume") {
            // FIX: Use Group to ensure injection covers both if/else branches
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
            // Inject into the Group (Covers both branches)
            .environmentObject(windowManager)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.5, height: 0.5, depth: 1, in: .meters)
                
        // User List Window
        WindowGroup(id: WindowType.userListWindow.rawValue) {
            UserListView()
                .environment(appModel)
                // FIX: Added missing injection
                .trackWindow(type: .userListWindow)  // ← This comes AFTER windowManager, which is correct
                .environmentObject(windowManager)
        }
        .defaultSize(width: 500, height: 600)
        .windowStyle(.plain)
        
        // Immersive space window for Spaces.
        ImmersiveSpace(id: appModel.spacesID) {
            SpacesView()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .environmentObject(spacesEntityWrapper)
                // Ensure WindowManager is injected for SpacesView and its Attachments
                .environmentObject(windowManager)
        }
        .handlesExternalEvents(
            // Use the string literals defined above
            matching: [publicSpaceActivityIdentifier, directCallActivityIdentifier]
        )
        .immersionStyle(selection: .constant(.full), in: .full)

        // UPDATED: ImmersiveSpace for Trivia with SharePlay
        ImmersiveSpace(id: "TriviaSpace") {
            TriviaSpaceView()
                .environmentObject(hostedEventManager)
                .environmentObject(personaManager)
                .environmentObject(triviaGameManager)
                .environmentObject(triviaSharePlayManager) // ADDED
                .task {
                    // ADDED: Listen for SharePlay sessions
                    for await session in TriviaEventActivity.sessions() {
                        await triviaSharePlayManager.configureGroupSession(session)
                    }
                }
        }
        
        // Audio Controls window.
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
        
        // Space Map window.
        WindowGroup("Space Map", id: WindowType.spaceMap.rawValue) {
            SpaceMapView()
                .environment(appModel)
                .environmentObject(ImmersiveSpaceManager.shared)
                .trackWindow(type: .spaceMap)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 800, height: 750)
        .windowStyle(.plain)
        
        // Space Nav Bar window.
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
        
        // Space Chat window.
        WindowGroup(id: WindowType.spaceChatWindow.rawValue) {
            SpacesChatWindow()
                .environment(appModel)
                .trackWindow(type: .spaceChatWindow)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)
        
        
        // Space Emoji window.
        WindowGroup(id: WindowType.spaceEmojiWindow.rawValue) {
            SpacesEmojiWindow()
                .environment(appModel)
                .trackWindow(type: .spaceEmojiWindow)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 300, height: 180)
        .windowStyle(.plain)
        
        // Chat Settings window.
        WindowGroup("Chat Settings", id: WindowType.chatSettings.rawValue) {
            ChatSettingsNavBar()
                .environment(appModel)
                .trackWindow(type: .chatSettings)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 350, height: 225)
        
        // UPDATED: Chat window for Movie Theatre with SharePlay
        WindowGroup(id: WindowType.chat.rawValue) {
            // FIX: Use Group for conditional content
            Group {
                if let event = appModel.currentEvent {
                    ChatView(viewModel: ChatViewModel(
                        eventId: event.id ?? "",
                        date: event.date,
                        eventManager: firebaseEventManager
                    ))
                    .environment(appModel)
                    .environmentObject(triviaSharePlayManager) // ADDED
                } else {
                    // Provide a fallback view or EmptyView
                    EmptyView()
                }
            }
            // FIX: Added missing injection
            .trackWindow(type: .chat)
            .environmentObject(windowManager)
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)
        
        // Nav Bar window for Movie Theatre. (Placeholder)
        
        // Movie window. (Placeholder)
        
        WindowGroup("Storyteller", id: WindowType.storytellerWindow.rawValue) {
            StoriesListView()
                .environment(appModel)
                .trackWindow(type: .storytellerWindow)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 1250, height: 800)
        .windowStyle(.plain)
        
        // Movement Control (Volumetric - tracking it ensures WindowManager can close it)
        WindowGroup(id: WindowType.movementControl.rawValue) {
            MovementControlView()
                .environment(appModel)
                // Added missing injection
                .trackWindow(type: .movementControl)
                .environmentObject(windowManager)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.4, height: 0.4, depth: 0.4, in: .meters)
        
        // Replace your current web browser WindowGroup with this simpler approach:
        // In your Movie_Theater_ExperienceApp.swift, replace your current browser WindowGroup with these:

        // Browser Window 1
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

        // Browser Window 2
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

        // Browser Window 3
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

        // Browser Window 4
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

        // Browser Window 5
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
        
        // UPDATED: Host Controls Window with SharePlay
        WindowGroup("Host Controls", id: "hostControls") {
            TriviaHostControlsView()
                .environmentObject(hostedEventManager)
                .environmentObject(triviaGameManager)
                .environmentObject(triviaSharePlayManager) // ADDED
        }
        .defaultSize(width: 1000, height: 800)
        
        // ADDED: SharePlay Test Window (for development/debugging)
        WindowGroup("SharePlay Debug", id: "sharePlayDebug") {
            SharePlayTestView()
                .environmentObject(triviaSharePlayManager)
                .environmentObject(hostedEventManager)
        }
        .defaultSize(width: 600, height: 400)
        .windowStyle(.plain)
        
        // Exiting window.
        WindowGroup(id: WindowType.exitingWindow.rawValue, for: WatchStats.self) { stats in
            // FIX: Use Group for conditional content
            Group {
                if let unwrappedStats = stats.wrappedValue {
                    ExitingWindow(stats: unwrappedStats)
                        .environment(appModel)
                } else {
                    EmptyView()
                }
            }
            // FIX: Added missing injection and tracking
            .trackWindow(type: .exitingWindow)
            .environmentObject(windowManager)
        }
        .defaultSize(width: 600, height: 800)
        .windowStyle(.plain)
    }
}

extension Movie_Theater_ExperienceApp {
    func openSpaceList() {
        // Assuming "spaceList" is an ID you might add later
        openWindow(id: "spaceList")
    }
}
