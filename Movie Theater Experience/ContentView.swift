import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    let events = [
        CalendarEvent(title: "Morning Meeting", date: Date().setting(hour: 6, minute: 0), end: Date().setting(hour: 10, minute: 30), description: "Discuss project updates"),
        CalendarEvent(title: "Lunch with Team", date: Date().setting(hour: 10, minute: 30), end: Date().setting(hour: 13, minute: 30), description: "Lunch at the cafe"),
        CalendarEvent(title: "Client Call", date: Date().setting(hour: 19, minute: 0), end: Date().setting(hour: 15, minute: 0), description: "Call with the client"),
        CalendarEvent(title: "Gym Workout", date: Date().setting(hour: 12, minute: 0), end: Date().setting(hour: 19, minute: 0), description: "Evening workout session")
    ]


    
    @State private var selectedTab: Int = 0

    var body: some View {
        HStack {
            // TabView on the side
            TabView(selection: $selectedTab) {
                // CalendarView Tab
                VStack {
                    CalendarView(events: events)
                        .padding()

                    ToggleImmersiveSpaceButton()
                        .padding(.top)
                }
                .tabItem {
                    Label("Current Showings", systemImage: "1.circle")
                }
                .tag(0)

                // Private Showing Tab
                Text("Private Showing")
                    .tabItem {
                        Label("Private Showing", systemImage: "2.circle")
                    }
                    .tag(1)

                // Settings Tab
                Text("Settings")
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(2)
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
