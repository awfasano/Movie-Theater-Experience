// SpacesNavBarView.swift
import SwiftUI

// MARK: - Notification Definitions
extension Notification.Name {
    /// Posted when the user's rotation changes.
    /// UserInfo: ["rotation": Float, "seat": String]
    static let userRotationChanged = Notification.Name("UserRotationChanged")

    /// Posted when the user's vertical offset changes.
    /// UserInfo: ["verticalOffset": Float, "seat": String]
    static let userVerticalOffsetChanged = Notification.Name("UserVerticalOffsetChanged")

    /// Used to trigger song fetching for a space.
    static let FetchSongsForSpace = Notification.Name("FetchSongsForSpace")
}

// MARK: - Spaces Nav Bar View
struct SpacesNavBarView: View {
    // MARK: - Environment
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var spacesEntityWrapper: SpacesEntityWrapper
    @EnvironmentObject private var windowManager: WindowManager

    // MARK: - State Properties
    
    // UI State
    @State private var isContentHidden: Bool = false
    
    // Transform State
    @State private var currentRotation: Float = 0.0
    private let rotationIncrement: Float = 5.0
    @State private var verticalOffset: Float = 0.0
    private let verticalIncrement: Float = 0.1

    // Button Animation State
    @State private var isOpeningMap = false
    @State private var isOpeningStoryteller = false
    @State private var isOpeningEmoji = false
    @State private var isOpeningUserList = false
    @State private var isOpeningChat = false
    @State private var isOpeningAudioControls = false
    @State private var isOpeningBrowser = false
    @State private var isOpeningSettings = false
    
    // Services
    @StateObject private var audioService = AudioService.shared
    
    var body: some View {
        HStack(spacing: 20) {
            // --- CORE CONTROLS ---
            
            Button(action: {
                Task {
                    // Just dismiss the space. The cleanupView() in SpacesView
                    // will handle closing all windows and opening the main one.
                    await dismissImmersiveSpace()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .help("Exit immersive space")
            
            Toggle(isOn: $spacesEntityWrapper.showEmojis) {
                Image(systemName: spacesEntityWrapper.showEmojis ? "eye.slash.fill" : "eye.fill")
            }
            .toggleStyle(.button)
            .help(spacesEntityWrapper.showEmojis ? "Hide Emojis" : "Show Emojis")

            Divider().frame(height: 20)
            
            // --- MOVEMENT CONTROLS ---
            VStack(spacing: 10) {
                // Rotation
                HStack(spacing: 10) {
                    Button(action: { rotateUser(degrees: -rotationIncrement) }) { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.bordered)
                    Text("\(Int(currentRotation))°")
                        .font(.caption).monospacedDigit().frame(width: 40).foregroundColor(.secondary)
                    Button(action: { rotateUser(degrees: rotationIncrement) }) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                }
                
                // Vertical Offset
                HStack(spacing: 10) {
                    Button(action: { moveUserVertically(amount: verticalIncrement) }) { Image(systemName: "arrow.down") }
                        .buttonStyle(.bordered)
                    Text("\(String(format: "%.1f", verticalOffset))m")
                        .font(.caption).monospacedDigit().frame(width: 40).foregroundColor(.secondary)
                    Button(action: { moveUserVertically(amount: -verticalIncrement) }) { Image(systemName: "arrow.up") }
                        .buttonStyle(.bordered)
                }
            }
            
            Divider().frame(height: 20)

            // --- WINDOW-OPENING BUTTONS ---

            // Seat Selection
            windowOpeningButton(id: "spaceMap", state: $isOpeningMap, systemImage: "chair.lounge", helpText: "Change seat")
            
            // Storyteller
            windowOpeningButton(id: "storytellerWindow", state: $isOpeningStoryteller, systemImage: "waveform", helpText: "Open stories")
            
            // Emoji Reactions
            windowOpeningButton(id: "spaceEmojiWindow", state: $isOpeningEmoji, systemImage: "face.smiling", helpText: "Send emoji reactions")

            // User List
            windowOpeningButton(id: "userListWindow", state: $isOpeningUserList, systemImage: "person.2.fill", helpText: "View active users")
            
            // Chat
            windowOpeningButton(id: "spaceChatWindow", state: $isOpeningChat, systemImage: "message.fill", helpText: "Open chat messages")
            
            // Music Controls
            Button(action: {
                openWindow(id: "audioControls")
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    if let space = appModel.selectedSpace, let entity = spacesEntityWrapper.getSpaceEntity() {
                        await audioService.loadSongsAndPreparePlayer(for: space.spaceName, rootEntity: entity)
                    }
                }
            }) {
                Image(systemName: "music.note")
            }
            .buttonStyle(.bordered)
            .help("Music Controls")
            
            // Web Browser
            windowOpeningButton(id: "webBrowserWindow", state: $isOpeningBrowser, systemImage: "safari.fill", helpText: "Open Web Browser")
            
            // Settings
            windowOpeningButton(id: "chatSettings", state: $isOpeningSettings, systemImage: "gear", helpText: "Open Settings")
        }
        .padding()
        // UPDATED: More opaque background options
        .background(.thickMaterial)
        
        // Alternative background options (replace .thickMaterial above with one of these):
        // .background(.regularMaterial)  // Even less translucent
        // .background(.bar)              // Most opaque material
        // .background(Color.black.opacity(0.3))  // Custom semi-transparent
        // .background(.thinMaterial)     // Still translucent but better than ultraThin
        .cornerRadius(10)
        .shadow(radius: 5)
        .opacity(isContentHidden ? 0.0 : 1.0)
    }
    
    // MARK: - Helper Functions
    
    private func rotateUser(degrees: Float) {
        currentRotation += degrees
        if currentRotation >= 360 { currentRotation -= 360 }
        else if currentRotation < 0 { currentRotation += 360 }
        
        let userInfo: [String: Any] = [
            "rotation": currentRotation,
            "seat": appModel.selectedSpace?.currentSeat ?? "seat_1"
        ]
        NotificationCenter.default.post(name: .userRotationChanged, object: nil, userInfo: userInfo)
    }
    
    private func moveUserVertically(amount: Float) {
        verticalOffset += amount
        
        let userInfo: [String: Any] = [
            "verticalOffset": verticalOffset,
            "seat": appModel.selectedSpace?.currentSeat ?? "seat_1"
        ]
        NotificationCenter.default.post(name: .userVerticalOffsetChanged, object: nil, userInfo: userInfo)
    }

    private func windowOpeningButton(id: String, state: Binding<Bool>, systemImage: String, helpText: String) -> some View {
        Button(action: {
            state.wrappedValue = true
            Task {
                try? await Task.sleep(for: .milliseconds(20))
                await MainActor.run { openWindow(id: id) }
                state.wrappedValue = false
            }
        }) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.bordered)
        .help(helpText)
        .scaleEffect(state.wrappedValue ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: state.wrappedValue)
    }
}

// MARK: - Preview
struct SpacesNavBarView_Previews: PreviewProvider {
    static var previews: some View {
        SpacesNavBarView()
            .environment(AppModel())
            .environmentObject(SpacesEntityWrapper.shared)
            .environmentObject(WindowManager())
            .glassBackgroundEffect()
    }
}
