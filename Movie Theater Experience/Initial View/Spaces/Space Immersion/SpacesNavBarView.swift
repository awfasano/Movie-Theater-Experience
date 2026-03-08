import SwiftUI

struct SpacesNavBarView: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    // Local state for toggling hide/show immersive view.
    @State private var isContentHidden: Bool = false

    var body: some View {
        HStack(spacing: 20) {
            // Exit immersive view
            Button(action: {
                Task {
                    await dismissImmersiveSpace()
                }
            }) {
                Label("Exit", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Exit immersive space")

            // Hide immersive view
            Button(action: {
                withAnimation {
                    isContentHidden.toggle()
                }
            }) {
                Label(isContentHidden ? "Show" : "Hide", systemImage: isContentHidden ? "eye.fill" : "eye.slash.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(isContentHidden ? "Show immersive content" : "Hide immersive content")

            // Seat Selection Button
            Button(action: {
                openWindow(id: "spaceMap")
            }) {
                Label("Change Seat", systemImage: "chair.lounge")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Change seat position")

            // Open Emoji Buttons Window
            Button(action: {
                openWindow(id: "spaceEmojiWindow")
            }) {
                Label("Emoji", systemImage: "face.smiling")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Open emoji reactions")

            // Open Chat Messages Window
            Button(action: {
                openWindow(id: "spaceChatWindow")
            }) {
                Label("Chat", systemImage: "message.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Open chat messages")

            Button(action: {
              openWindow(id: "audioControls")
            }) {
              Label("Volume", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Open audio controls")

        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(radius: 5)
        .opacity(isContentHidden ? 0.0 : 1.0)
    }
}
