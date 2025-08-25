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
    
    /// Portal notifications
    static let setupPortal = Notification.Name("SetupPortal")
    static let removePortal = Notification.Name("RemovePortal")
    static let updatePortalTransparency = Notification.Name("UpdatePortalTransparency")
    static let startAmbientAudio = Notification.Name("StartAmbientAudio")
    static let stopAmbientAudio = Notification.Name("StopAmbientAudio")
    static let updateAmbientVolume = Notification.Name("UpdateAmbientVolume")
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
    @State private var ambientAudioEnabled: Bool = true
    @State private var showVolumeSlider = false
    @State private var ambientVolume: Float = 0.0  // 0 dB = full volume

    // Button Animation State
    @State private var isOpeningMap = false
    @State private var isOpeningStoryteller = false
    @State private var isOpeningEmoji = false
    @State private var isOpeningUserList = false
    @State private var isOpeningChat = false
    @State private var isOpeningAudioControls = false
    @State private var isOpeningBrowser = false
    @State private var isOpeningSettings = false
    @State private var isOpeningPortal = false
    
    // Services
    @StateObject private var audioService = AudioService.shared
        
    var body: some View {
        HStack(spacing: 20) {
            // --- CORE CONTROLS ---
            
            Button(action: {
                Task {
                    await dismissImmersiveSpace()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .help("Exit immersive space")
            
            Toggle(isOn: $spacesEntityWrapper.showEmojis) {
                Image(systemName: spacesEntityWrapper.showEmojis ? "eye.fill" : "eye.slash.fill")
            }
            .toggleStyle(.button)
            .help(spacesEntityWrapper.showEmojis ? "Hide Emojis" : "Show Emojis")

            Divider().frame(height: 20)
            
            // --- MOVEMENT CONTROLS ---
            VStack(spacing: 10) {
                // Rotation
                HStack(spacing: 10) {
                    Button(action: { rotateUser(degrees: -rotationIncrement) }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    
                    Text("\(Int(currentRotation))°")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 40)
                        .foregroundColor(.secondary)
                    
                    Button(action: { rotateUser(degrees: rotationIncrement) }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                
                // Vertical Offset
                HStack(spacing: 10) {
                    Button(action: { moveUserVertically(amount: verticalIncrement) }) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    
                    Text("\(String(format: "%.1f", -verticalOffset))m")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 40)
                        .foregroundColor(.secondary)
                    
                    Button(action: { moveUserVertically(amount: -verticalIncrement) }) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Divider().frame(height: 20)

            // --- WINDOW-OPENING BUTTONS ---
            
            windowOpeningButton(id: "spaceMap", state: $isOpeningMap, systemImage: "chair.lounge", helpText: "Change seat")
            windowOpeningButton(id: "storytellerWindow", state: $isOpeningStoryteller, systemImage: "waveform", helpText: "Open stories")
            windowOpeningButton(id: "spaceEmojiWindow", state: $isOpeningEmoji, systemImage: "face.smiling", helpText: "Send emoji reactions")
            windowOpeningButton(id: "spaceChatWindow", state: $isOpeningChat, systemImage: "message.fill", helpText: "Open chat messages")
            
            // --- AUDIO CONTROLS ---
            
            // Volume Control Button
            Button(action: {
                showVolumeSlider.toggle()
            }) {
                Image(systemName: "slider.vertical.3")
            }
            .buttonStyle(.bordered)
            .help("Adjust volume")
            .disabled(!ambientAudioEnabled)
            // This is the correct way to show the slider.
            .popover(isPresented: $showVolumeSlider,
                     attachmentAnchor: .point(.top),
                     arrowEdge: .bottom) {
                volumeSliderPopover
            }
            
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
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.bar)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.8))
                }
        }
        .cornerRadius(10)
        .shadow(radius: 5)
        .opacity(isContentHidden ? 0.0 : 1.0)
    }
    
    // MARK: - Volume Slider Popover
    // MARK: - Volume Slider Popover
    // MARK: - Volume Slider Popover
    private var volumeSliderPopover: some View {
        VStack(spacing: 8) {
            volumeHighIcon
            volumeSliderTrack
            volumeLowIcon
            volumeDisplay
                .padding(.top, 4)
        }
        // Add padding around the content inside the popover bubble.
        .padding(.vertical)
        // The custom .background modifier has been removed.
    }

    
    private var volumeDisplay: some View {
        Text("\(Int(ambientVolume))%")
            .font(.caption)
            .monospacedDigit()
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
    
    private var volumeHighIcon: some View {
        Image(systemName: "speaker.wave.3.fill")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
    
    private var volumeLowIcon: some View {
        Image(systemName: "speaker.fill")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
    
    private var volumeSliderTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background track
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 6)

                // Active fill based on 0-100 range
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: CGFloat(ambientVolume / 100.0) * geometry.size.height)

                // Thumb positioned precisely
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(radius: 2)
                    .position(x: geometry.size.width / 2,
                              y: CGFloat(1 - (ambientVolume / 100.0)) * geometry.size.height)
            }
            .frame(width: 20)
            .gesture(volumeDragGesture(in: geometry.size.height))
        }
        .frame(width: 20, height: 150)
    }

    private func volumeDragGesture(in height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Clamp the drag location to the bounds of the slider
                let clampedY = max(0, min(value.location.y, height))
                let percent = 1.0 - (clampedY / height)
                
                // Calculate new value based on 0-100 range
                let newValue = Float(percent * 100.0)
                ambientVolume = max(0.0, min(100.0, newValue))
                
                updateAmbientVolume(ambientVolume)
            }
    }


    
    private func handleVolumeChange(at xPosition: CGFloat, in width: CGFloat) {
        let percent = xPosition / width
        let newValue = Float(-60.0 + (60.0 * percent))
        ambientVolume = max(-60.0, min(0.0, newValue))
        updateAmbientVolume(ambientVolume)
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
    
    private func updateAmbientVolume(_ volume: Float) {
        guard ambientAudioEnabled else { return }
        
        let userInfo: [String: Any] = [
            "volume": volume
        ]
        NotificationCenter.default.post(
            name: .updateAmbientVolume,
            object: nil,
            userInfo: userInfo
        )
    }

    private func windowOpeningButton(id: String, state: Binding<Bool>, systemImage: String, helpText: String, customAction: (() -> Void)? = nil) -> some View {
        Button(action: {
            state.wrappedValue = true
            Task {
                try? await Task.sleep(for: .milliseconds(20))
                if let customAction = customAction {
                    customAction()
                } else {
                    await MainActor.run { openWindow(id: id) }
                }
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
    
    private func setupWorldPortal() async {
        // Post notification to SpacesView to setup portal
        NotificationCenter.default.post(name: .setupPortal, object: nil)
    }

    private func removePortal() {
        // Post notification to SpacesView to remove portal
        NotificationCenter.default.post(name: .removePortal, object: nil)
    }
    
    private func getVisibilityDescription() -> String {
        let percentage = Int(appModel.viewTransparency)
        switch percentage {
        case 0:
            return "Everything hidden"
        case 1..<25:
            return "Showing top portion"
        case 25..<50:
            return "Showing upper half"
        case 50:
            return "Half visible"
        case 51..<75:
            return "Mostly visible"
        case 75..<100:
            return "Nearly full"
        case 100:
            return "Fully visible"
        default:
            return ""
        }
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
