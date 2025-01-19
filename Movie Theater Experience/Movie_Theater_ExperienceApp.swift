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
        WindowGroup("Tab Bar", id: "tabBar") {
            if #available(visionOS 2.0, *) {
                TabBarWindow()
                    .environment(appModel)
                    .environmentObject(sharedSelection)
                    .environmentObject(theatreEntityWrapper)
            }
        }
        .defaultSize(width: 1000, height: 600)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            if #available(visionOS 2.0, *) {
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
        }
        .immersionStyle(selection: .constant(.full), in: .full)

        WindowGroup("Seat Map", id: "seatMap") {
            SeatMapView()
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
        }

        WindowGroup("Emoji Window", id: "emojiWindow") {
            if let event = appModel.currentEvent {
                EmojiButtonView(eventId: event.id ?? "", date: event.date)
                    .background(Color.clear)
            }
        }
        .defaultSize(width: 300, height: 100)
        .windowStyle(.plain)

        WindowGroup(id: "chatWindow") {
            if let event = appModel.currentEvent {
                ChatView(viewModel: ChatViewModel(
                    eventId: event.id ?? "",
                    date: event.date
                ))
            }
        }
        .defaultSize(width: 400, height: 600)
        .windowStyle(.plain)

        WindowGroup("Nav Bar", id: "navBar") {
            NavBarView()
                .environment(appModel)
                .environmentObject(sharedSelection)
                .environmentObject(theatreEntityWrapper)
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 50)
        
        WindowGroup("Movie Window", id: "movieWindow") {
            MovieWindow()
                .environment(appModel)
        }
        .defaultSize(width: 500, height: 350)
        .windowStyle(.plain)
    }
}
