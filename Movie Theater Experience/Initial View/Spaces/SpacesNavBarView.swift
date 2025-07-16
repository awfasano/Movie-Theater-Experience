import SwiftUI

struct SpacesNavBarView: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var spacesEntityWrapper: SpacesEntityWrapper
    @EnvironmentObject private var windowManager: WindowManager

    // MARK: - State Properties
    @State private var showTransparencyControl = false
    @State private var isContentHidden: Bool = false
    @State private var currentRotation: Float = 0.0
    private let rotationIncrement: Float = 5.0

    // State for button animations
    @State private var isOpeningMap = false
    @State private var isOpeningStoryteller = false
    @State private var isOpeningEmoji = false
    @State private var isOpeningUserList = false
    @State private var isOpeningChat = false
    @State private var isOpeningAudioControls = false
    
    // Get the shared audio service instance
    @StateObject private var audioService = AudioService.shared
    
    var body: some View {
        HStack(spacing: 20) {
            // --- NON-WINDOW BUTTONS ---
            
            Button(action: {
                Task { await exitImmersiveSpace() }
            }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .help("Exit immersive space")
            
            Button(action: {
                withAnimation { isContentHidden.toggle() }
            }) {
                Image(systemName: isContentHidden ? "eye.fill" : "eye.slash.fill")
            }
            .buttonStyle(.bordered)
            .help(isContentHidden ? "Show interface" : "Hide interface")
            
            Divider().frame(height: 20)
            
            HStack(spacing: 10) {
                Button(action: { rotateUser(degrees: -rotationIncrement) }) { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.bordered)
                Text("\(Int(currentRotation))°")
                    .font(.caption).monospacedDigit().frame(width: 40).foregroundColor(.secondary)
                Button(action: { rotateUser(degrees: rotationIncrement) }) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered)
            }
            
            Divider().frame(height: 20)

            // --- WINDOW-OPENING BUTTONS ---

            // Seat Selection Button
            Button(action: {
                isOpeningMap = true
                Task {
                    try? await Task.sleep(for: .milliseconds(20))
                    await MainActor.run { openWindow(id: "spaceMap") }
                    isOpeningMap = false
                }
            }) {
                Image(systemName: "chair.lounge")
            }
            .buttonStyle(.bordered)
            .help("Change seat")
            .scaleEffect(isOpeningMap ? 1.2 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOpeningMap)
            
            // Storyteller Button
            Button(action: {
                isOpeningStoryteller = true
                Task {
                    try? await Task.sleep(for: .milliseconds(20))
                    await MainActor.run { openWindow(id: "storytellerWindow") }
                    isOpeningStoryteller = false
                }
            }) {
                Image(systemName: "waveform")
            }
            .buttonStyle(.bordered)
            .help("Open stories")
            .scaleEffect(isOpeningStoryteller ? 1.2 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOpeningStoryteller)
            
            // Emoji Buttons Window
            Button(action: {
                isOpeningEmoji = true
                Task {
                    try? await Task.sleep(for: .milliseconds(20))
                    await MainActor.run { openWindow(id: "spaceEmojiWindow") }
                    isOpeningEmoji = false
                }
            }) {
                Image(systemName: "face.smiling")
            }
            .buttonStyle(.bordered)
            .help("Send emoji reactions")
            .scaleEffect(isOpeningEmoji ? 1.2 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOpeningEmoji)
            
            // User List Window
            Button(action: {
                isOpeningUserList = true
                Task {
                    try? await Task.sleep(for: .milliseconds(20))
                    await MainActor.run { openWindow(id: "userListWindow") }
                    isOpeningUserList = false
                }
            }) {
                Image(systemName: "person.2.fill")
            }
            .buttonStyle(.bordered)
            .help("View active users")
            .scaleEffect(isOpeningUserList ? 1.2 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOpeningUserList)
            

            // ADD THIS BUTTON:
            /*
            Button {
                 showTransparencyControl.toggle()
             } label: {
                 Image(systemName: "slider.horizontal.below.rectangle")
                     .font(.title2)
             }
             .buttonStyle(.plain)
             .popover(isPresented: $showTransparencyControl, arrowEdge: .bottom) {
                 // This now correctly references the `@State` variable
                 TransparencyControlView()
             }
            */
            // Chat Messages Window
            Button(action: {
                isOpeningChat = true
                Task {
                    try? await Task.sleep(for: .milliseconds(20))
                    await MainActor.run { openWindow(id: "spaceChatWindow") }
                    isOpeningChat = false
                }
            }) {
                Image(systemName: "message.fill")
            }
            .buttonStyle(.bordered)
            .help("Open chat messages")
            .scaleEffect(isOpeningChat ? 1.2 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOpeningChat)
            
            // ✅ FIXED Music Controls Button
            Button(action: {
                // 1. Open the window immediately. This makes the UI feel instant.
                openWindow(id: "audioControls")

                // 2. Prepare the audio in a background task.
                Task {
                    // This tiny delay gives the window animation a head start, preventing stutter.
                    try? await Task.sleep(for: .milliseconds(50))
                    
                    // The service itself prevents re-doing work, so this is safe to call.
                    if let space = appModel.selectedSpace, let entity = spacesEntityWrapper.getSpaceEntity() {
                        await audioService.loadSongsAndPreparePlayer(for: space.spaceName, rootEntity: entity)
                    }
                }
            }) {
                Image(systemName: "music.note")
            }
            .buttonStyle(.bordered)
            .help("Music Controls")
            
            
            
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(radius: 5)
        .opacity(isContentHidden ? 0.0 : 1.0)
    }
    
    // MARK: - Helper Functions
    
    private func rotateUser(degrees: Float) {
        currentRotation += degrees
        if currentRotation >= 360 { currentRotation -= 360 }
        else if currentRotation < 0 { currentRotation += 360 }
        applyRotation()
    }
    
    private func applyRotation() {
        let userInfo: [String: Any] = [
            "rotation": currentRotation,
            "seat": appModel.selectedSpace?.currentSeat ?? "seat_1"
        ]
        NotificationCenter.default.post(
            name: .userRotationChanged,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func openWindowWithAnimation(id: String, state: Binding<Bool>) {
        state.wrappedValue = true
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            await MainActor.run { openWindow(id: id) }
            state.wrappedValue = false
        }
    }
    
    private func exitImmersiveSpace() {
        Task {
            await dismissImmersiveSpace()
            try? await Task.sleep(for: .milliseconds(100))
            
            await withTaskGroup(of: Void.self) { group in
                let windowIDs = [
                    "spaceNavBar", "spaceMap", "spaceChatWindow", "spaceEmojiWindow",
                    "audioControls", "storytellerWindow", "userListWindow", "volume",
                    "tabBar", "chatWindow", "emojiWindow", "movieWindow",
                    "navBar", "exitingWindow", "chatSettings"
                ]
                for id in windowIDs {
                    group.addTask { await MainActor.run { dismissWindow(id: id) } }
                }
            }
            
            await MainActor.run {
                appModel.selectedSpace = nil
                appModel.currentActiveSpace = nil
                windowManager.closeAllWindows()
            }
            
            try? await Task.sleep(for: .milliseconds(200))
            await MainActor.run { openWindow(id: "mainContent") }
        }
    }
}

extension Notification.Name {
    static let userRotationChanged = Notification.Name("UserRotationChanged")
    static let FetchSongsForSpace = Notification.Name("FetchSongsForSpace")
}
