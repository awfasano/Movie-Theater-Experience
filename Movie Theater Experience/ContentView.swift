import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// Assuming this is where SpacesView is created
WindowGroup("Spaces", id: "spacesWindow") {
    SpacesView()
        .environmentObject(selectedSpace)
} 