import SwiftUI
import RealityKit
// import RealityKitContent // Uncomment if needed

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabBarWindow()
    }
}

extension View {
    func ensureVisibilityAfterImmersiveExit() -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReturnToContentView"))) { _ in
                print("📱 ContentView received return notification")
                
                // Force the view to refresh
                Task { @MainActor in
                    // Any state updates needed to refresh ContentView
                }
            }
            .onAppear {
                print("📱 ContentView appeared")
            }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
