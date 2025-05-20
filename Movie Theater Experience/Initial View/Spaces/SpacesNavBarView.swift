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
            
            // Hide immersive view
            Button(action: {
                withAnimation {
                    isContentHidden.toggle()
                }
            }) {
                Label(isContentHidden ? "Show" : "Hide", systemImage: isContentHidden ? "eye.fill" : "eye.slash.fill")
            }
            .buttonStyle(.bordered)
            
            // Seat Selection Button
            Button(action: {
                openWindow(id: "spaceMap")
            }) {
                Label("Change Seat", systemImage: "chair.lounge")
            }
            .buttonStyle(.bordered)
            
            
            Button(action: {
                openWindow(id: "storytellerWindow")
            }) {
                Label("Stories", systemImage: "waveform")
            }
            .buttonStyle(.bordered)
            
            
            // Open Emoji Buttons Window
            Button(action: {
                openWindow(id: "spaceEmojiWindow")
            }) {
                Label("Emoji", systemImage: "face.smiling")
            }
            .buttonStyle(.bordered)
            
            // Open Chat Messages Window
            Button(action: {
                openWindow(id: "spaceChatWindow")
            }) {
                Label("Chat", systemImage: "message.fill")
            }
            .buttonStyle(.bordered)
            
            Button(action: {
              openWindow(id: "audioControls")
            }) {
              Label("Volume", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(radius: 5)
        .opacity(isContentHidden ? 0.0 : 1.0)
    }
}
