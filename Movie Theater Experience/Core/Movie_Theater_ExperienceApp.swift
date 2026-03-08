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

    // Other managers and wrappers.
    @StateObject private var immersiveSpaceManager = ImmersiveSpaceManager.shared
    @StateObject private var sharedSelection = SharedSeatSelection.shared
    @StateObject private var selectedSpace = SelectedSpace()
    @StateObject private var theatreEntityWrapper = TheatreEntityWrapper.shared
    @StateObject private var windowManager = WindowManager()
    @StateObject private var spacesEntityWrapper = SpacesEntityWrapper.shared

    // Inject additional managers.
    @StateObject private var firebaseEventManager = FirebaseEventManager.shared
    @StateObject private var emojiManager = EmojiManager.shared

    // Space-related managers.
    @StateObject private var spacesChatManager = SpacesChatManager.shared

    @Environment(\.openWindow) var openWindow
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("userId") var userId: String = ""

    var body: some Scene {
        // Main content window (launch window + reopenable by WindowManager).
        WindowGroup(id: WindowType.mainContent.rawValue) {
            TabBarWindow()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSelection)
                .environmentObject(selectedSpace)
                .environmentObject(theatreEntityWrapper)
                .environmentObject(firebaseEventManager)
                .environmentObject(windowManager)
                .trackWindow(type: .mainContent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Task { await VideoSyncService.shared.cleanup(level: .full) }
                    }
                }
                .onAppear {
                    if userId.isEmpty {
                        userId = UUID().uuidString
                    }
                }
        }
        .defaultSize(width: 1000, height: 600)

        // Volumetric preview window.
        WindowGroup("Volume", id: WindowType.volume.rawValue) {
            Group {
                if let spaceData = appModel.selectedSpace {
                    VolumetricSpaceWrapper(space: spaceData)
                        .environment(appModel)
                        .environmentObject(immersiveSpaceManager)
                        .environmentObject(sharedSelection)
                        .environmentObject(theatreEntityWrapper)
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
        .defaultSize(width: 600, height: 350)

        // Immersive space window for movie experience.
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            if #available(visionOS 1.0, *) {
                ImmersiveView()
                    .environment(appModel)
                    .environmentObject(immersiveSpaceManager)
                    .environmentObject(sharedSelection)
                    .environmentObject(theatreEntityWrapper)
                    .environmentObject(windowManager)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)

        // Immersive space window for Spaces.
        ImmersiveSpace(id: appModel.spacesID) {
            if #available(visionOS 1.0, *) {
                SpacesView(audioLoader: AudioService.shared.audioLoader)
                    .environment(appModel)
                    .environmentObject(immersiveSpaceManager)
                    .environmentObject(spacesEntityWrapper)
                    .environmentObject(windowManager)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)

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
                .environmentObject(immersiveSpaceManager)
                .trackWindow(type: .spaceMap)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 1600, height: 1300)
        .windowStyle(.plain)

        // Space Nav Bar window.
        WindowGroup("Space Nav Bar", id: WindowType.spaceNavBar.rawValue) {
            SpacesNavBarView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .trackWindow(type: .spaceNavBar)
                .environmentObject(windowManager)
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 50)

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

        // Emoji window (Movie Theatre).
        WindowGroup("Emoji Window", id: WindowType.emoji.rawValue) {
            if let event = appModel.currentEvent {
                EmojiButtonView(eventId: event.id ?? "", date: event.date)
                    .environmentObject(emojiManager)
                    .background(Color.clear)
                    .trackWindow(type: .emoji)
                    .environmentObject(windowManager)
            }
        }
        .defaultSize(width: 300, height: 100)
        .windowStyle(.plain)

        // Chat window (Movie Theatre).
        WindowGroup(id: WindowType.chat.rawValue) {
            Group {
                if let event = appModel.currentEvent {
                    ChatView(viewModel: ChatViewModel(
                        eventId: event.id ?? "",
                        date: event.date,
                        eventManager: firebaseEventManager
                    ))
                    .environment(appModel)
                } else {
                    EmptyView()
                }
            }
            .trackWindow(type: .chat)
            .environmentObject(windowManager)
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)

        // Nav Bar window (Movie Theatre).
        WindowGroup("Nav Bar", id: WindowType.navBar.rawValue) {
            NavBarView()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .trackWindow(type: .navBar)
                .environmentObject(windowManager)
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 50)

        // Movie window.
        WindowGroup("Movie Window", id: WindowType.movie.rawValue) {
            MovieWindow()
                .environment(appModel)
                .environmentObject(immersiveSpaceManager)
                .trackWindow(type: .movie)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 600, height: 1500)
        .windowStyle(.plain)

        // Exiting window.
        WindowGroup(id: WindowType.exitingWindow.rawValue, for: WatchStats.self) { stats in
            if let unwrappedStats = stats.wrappedValue {
                ExitingWindow(stats: unwrappedStats)
                    .trackWindow(type: .exitingWindow)
                    .environmentObject(windowManager)
            }
        }
        .defaultSize(width: 600, height: 800)
        .windowStyle(.plain)

        // Storyteller window.
        WindowGroup("Storyteller", id: WindowType.storytellerWindow.rawValue) {
            StoriesListView()
                .environment(appModel)
                .trackWindow(type: .storytellerWindow)
                .environmentObject(windowManager)
        }
        .defaultSize(width: 1250, height: 800)
        .windowStyle(.plain)

        // Movement Control (Volumetric).
        WindowGroup(id: WindowType.movementControl.rawValue) {
            MovementControlView()
                .environment(appModel)
                .trackWindow(type: .movementControl)
                .environmentObject(windowManager)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.4, height: 0.4, depth: 0.4, in: .meters)

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
    }
}

extension Movie_Theater_ExperienceApp {
    func openSpaceList() {
        openWindow(id: "spaceList")
    }
}
