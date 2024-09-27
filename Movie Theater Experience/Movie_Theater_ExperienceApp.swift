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
    @State private var appModel = AppModel()
    @StateObject var sharedSelection = SharedSeatSelection.shared
    @StateObject var theatreEntityWrapper = TheatreEntityWrapper()
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        WindowGroup("Content View", id: "contentView") {
            ContentView()
                .environment(appModel)
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.full), in: .full)

        // Existing WindowGroups
        WindowGroup("Seat Map", id: "seatMap") {
            SeatMapView()
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
        }
        WindowGroup("Emoji Window", id: "emojiWindow") {
            EmojiButtonView()
                .background(Color.clear)
        }
        .defaultSize(width: 300, height: 100)
        .windowStyle(.plain)

        WindowGroup(id: "chatWindow") {
            ChatView(viewModel: ChatViewModel(chatId: "uBTRnFJxunu2B2V4qIPK"))
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)

        // Nav Bar WindowGroup
        WindowGroup("Nav Bar", id: "navBar") {
            NavBarView()
                .environment(appModel)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 50)
    }
}
