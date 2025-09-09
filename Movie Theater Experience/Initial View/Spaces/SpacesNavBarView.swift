// SpacesNavBarView.swift
import SwiftUI
import Combine

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
    
    /// Audio state change notifications
    static let ambientAudioStateChanged = Notification.Name("AmbientAudioStateChanged")
}

struct SpacesNavBarView: View {
    // MARK: - Environment
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var spacesEntityWrapper: SpacesEntityWrapper
    @EnvironmentObject private var windowManager: WindowManager

    // MARK: - State Properties
    @State private var isContentHidden: Bool = false
    @State private var ambientVolume: Float = 75.0
    @State private var currentRotation: Float = 0.0
    private let rotationIncrement: Float = 5.0
    @State private var verticalOffset: Float = 0.0
    private let verticalIncrement: Float = 0.1
    @State private var ambientAudioEnabled: Bool = true
    @State private var isAudioPlaying: Bool = false  // Track actual playback state
    @State private var showVolumeSlider = false
    @State private var showInfoPopover = false
    
    
    // Button Animation State
    @State private var isExiting = false
    @State private var isOpeningMap = false
    @State private var isOpeningStoryteller = false
    @State private var isOpeningEmoji = false
    @State private var isOpeningUserList = false
    @State private var isOpeningChat = false
    @State private var isOpeningAudioControls = false
    @State private var isOpeningBrowser = false
    @State private var isOpeningSettings = false
    
    @StateObject private var audioService = AudioService.shared
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        HStack(spacing: 20) {
            // --- ENHANCED EXIT BUTTON ---
            Button(action: {
                Task {
                    await handleSmartExit()
                }
            }) {
                if isExiting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExiting)
            .help("Exit immersive space")
            
            Toggle(isOn: $spacesEntityWrapper.showEmojis) {
                Image(systemName: spacesEntityWrapper.showEmojis ? "eye.fill" : "eye.slash.fill")
            }
            .toggleStyle(.button)
            .help(spacesEntityWrapper.showEmojis ? "Hide Emojis" : "Show Emojis")
            
            Button(action: {
                showInfoPopover.toggle()
            }) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.bordered)
            .help("Control overview")
            .popover(isPresented: $showInfoPopover,
                     attachmentAnchor: .point(.bottom),
                     arrowEdge: .top) {
                controlsOverviewPopover
            }
            
            
            Divider().frame(height: 20)
            
            // --- MOVEMENT CONTROLS ---
            VStack(spacing: 10) {
                // Rotation controls
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
                
                // Vertical Offset controls
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
            
            // Rest of your buttons...
            windowOpeningButton(id: "spaceMap", state: $isOpeningMap, systemImage: "chair.lounge", helpText: "Change seat")
            windowOpeningButton(id: "storytellerWindow", state: $isOpeningStoryteller, systemImage: "waveform", helpText: "Open stories")
            windowOpeningButton(id: "spaceEmojiWindow", state: $isOpeningEmoji, systemImage: "face.smiling", helpText: "Send emoji reactions")
            windowOpeningButton(id: "spaceChatWindow", state: $isOpeningChat, systemImage: "message.fill", helpText: "Open chat messages")
            
            // Audio controls...
            HStack(spacing: 10) {
                Button(action: {
                    if isAudioPlaying {
                        // Audio is playing, so stop it
                        stopAmbientAudio()
                        ambientAudioEnabled = false
                    } else {
                        // Audio is not playing, so start it
                        ambientAudioEnabled = true
                        startAmbientAudio()
                        updateAmbientVolume(ambientVolume)
                    }
                }) {
                    Image(systemName: audioButtonIcon)
                        .foregroundColor(isAudioPlaying ? .primary : .secondary)
                }
                .buttonStyle(.bordered)
                .help(isAudioPlaying ? "Stop ambient audio" : "Start ambient audio")
                
                Button(action: {
                    showVolumeSlider.toggle()
                }) {
                    Image(systemName: "slider.vertical.3")
                        .foregroundColor(isAudioPlaying ? .primary : .secondary)
                }
                .buttonStyle(.bordered)
                .help("Adjust volume")
                .disabled(!isAudioPlaying)  // Disable when not playing
                .popover(isPresented: $showVolumeSlider,
                         attachmentAnchor: .point(.top),
                         arrowEdge: .bottom) {
                    volumeSliderPopover
                }
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
        .onAppear {
            setupAudioStateListeners()
        }
        .onDisappear {
            cancellables.removeAll()
        }
    }
    
    // MARK: - Audio State Monitoring
    private var audioButtonIcon: String {
        if !ambientAudioEnabled || !isAudioPlaying {
            return "speaker.slash.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
    
    private func setupAudioStateListeners() {
        // Listen for audio state changes
        NotificationCenter.default.publisher(for: .ambientAudioStateChanged)
            .sink { notification in
                if let isPlaying = notification.userInfo?["isPlaying"] as? Bool {
                    Task { @MainActor in
                        self.isAudioPlaying = isPlaying
                        
                        // If audio stopped unexpectedly, update our enabled state
                        if !isPlaying {
                            self.ambientAudioEnabled = false
                        }
                    }
                }
            }
            .store(in: &cancellables)
        
        // Monitor audio playing state every few seconds
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                checkAudioPlayingState()
            }
            .store(in: &cancellables)
    }
    
    private func checkAudioPlayingState() {
        guard let entity = spacesEntityWrapper.getSpaceEntity(),
              let rootEntity = entity.findEntity(named: "Root") else {
            isAudioPlaying = false
            return
        }
        
        let actuallyPlaying = AmbientAudioManager.shared.isAudioPlaying(for: rootEntity)
        if actuallyPlaying != isAudioPlaying {
            isAudioPlaying = actuallyPlaying
            ambientAudioEnabled = actuallyPlaying
        }
    }
    
    // MARK: - Smart Exit Handler
    @MainActor
    private func handleSmartExit() async {
        guard !isExiting else { return }
        isExiting = true
        
        defer { isExiting = false }
        
        print("🚪 [SpacesNavBar] Initiating smart exit sequence")
        
        // Check if we have an active entity in the space
        let hasActiveEntity = spacesEntityWrapper.getSpaceEntity() != nil
        let hasRootEntity = spacesEntityWrapper.getSpaceEntity()?.findEntity(named: "Root") != nil
        
        if !hasActiveEntity || !hasRootEntity {
            print("⚠️ [SpacesNavBar] No active entity/root detected - performing emergency exit")
            // Use the WindowManager's emergency exit method
            await windowManager.performEmergencyExit(
                dismissWindow: dismissWindow,
                openWindow: openWindow,
                dismissImmersiveSpace: { await dismissImmersiveSpace() }
            )
            
            // Clean up app state
            await appModel.cleanupImmersiveSpace()
        } else {
            print("✅ [SpacesNavBar] Active entity found - normal exit")
            // Normal dismissal - SpacesView will handle cleanup
            await dismissImmersiveSpace()
        }
    }
    
    // MARK: - Volume Slider Popover
    private var volumeSliderPopover: some View {
        VStack(spacing: 16) {
            Image(systemName: volumeIconName)
                .font(.largeTitle)
                .foregroundColor(isAudioPlaying ? .primary : .secondary)
            
            volumeSliderTrack
            volumeDisplay
        }
        .padding()
        .frame(width: 100)
    }
    
    private var volumeIconName: String {
        if !isAudioPlaying || ambientVolume == 0 {
            return "speaker.fill"
        } else if ambientVolume < 33 {
            return "speaker.wave.1.fill"
        } else if ambientVolume < 66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    // MARK: - User Controls
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
    
    // MARK: - Audio Controls
    private func startAmbientAudio() {
        NotificationCenter.default.post(name: .startAmbientAudio, object: nil)
        
        // Update state optimistically, but will be confirmed by state listener
        ambientAudioEnabled = true
    }
    
    private func stopAmbientAudio() {
        NotificationCenter.default.post(name: .stopAmbientAudio, object: nil)
        
        // Update state optimistically
        ambientAudioEnabled = false
        isAudioPlaying = false
    }
    
    private func updateAmbientVolume(_ volume: Float) {
        // Only update volume if audio is actually playing
        guard isAudioPlaying else {
            print("📝 Volume change ignored - audio not playing")
            return
        }
        
        let userInfo: [String: Any] = ["volume": volume]
        NotificationCenter.default.post(name: .updateAmbientVolume, object: nil, userInfo: userInfo)
    }
    
    // MARK: - Controls Overview Popover
    private var controlsOverviewPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Space Controls Overview")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                VStack(alignment: .leading, spacing: 12) {
                    controlDescription(icon: "eye.fill", title: "Show/Hide Emojis", description: "Toggle visibility of emoji reactions in the space")
                    
                    Divider()
                    
                    Text("Movement Controls")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    controlDescription(icon: "arrow.counterclockwise", title: "Rotate View", description: "Rotate your view left and right in 5° increments")
                    controlDescription(icon: "arrow.up", title: "Vertical Position", description: "Adjust your height up and down in 0.1m increments")
                    
                    Divider()
                    
                    Text("Windows & Features")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    controlDescription(icon: "chair.lounge", title: "Change Seat", description: "Switch to a different seat in the space")
                    controlDescription(icon: "waveform", title: "Stories", description: "Access audio stories and content")
                    controlDescription(icon: "face.smiling", title: "Emoji Reactions", description: "Send emoji reactions to other users")
                    controlDescription(icon: "message.fill", title: "Chat", description: "Open text chat with other users")
                    
                    Divider()
                    
                    Text("Audio Controls")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    controlDescription(icon: "speaker.wave.2.fill", title: "Ambient Audio", description: "Start/stop ambient background audio.  If the ambient audio stops at any point, just toggle it off and back on, and it should work again")
                    controlDescription(icon: "slider.vertical.3", title: "Volume Control", description: "Adjust ambient audio volume.  If you are having issues with the volume.  You make need to go to the control panel and increase volume for applications")
                    controlDescription(icon: "music.note", title: "Music Player", description: "Control spatial music playback")
                    
                    Divider()
                    
                    Text("Additional Features")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    controlDescription(icon: "safari.fill", title: "Web Browser", description: "Browse the internet, toggle for day or night mode, and save bookmarks")
                    controlDescription(icon: "gear", title: "Settings", description: "Adjust color preferences on buttons and chat messages")
                }
            }
            .padding()
        }
        .frame(width: 350, height: 500)
    }

    private func controlDescription(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
    
    
    
    // MARK: - Helper Methods
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
    
    private var volumeDisplay: some View {
        VStack(spacing: 4) {
            Text("\(Int(ambientVolume))%")
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(isAudioPlaying ? .primary : .secondary)
            
            Text("Volume")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }
    
    private var volumeSliderTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 14)
                
                Capsule()
                    .fill(isAudioPlaying ? Color.accentColor : Color.gray)
                    .frame(width: 14, height: CGFloat(ambientVolume / 100.0) * geometry.size.height)
                
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 36, height: 36)
                        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                        .overlay(
                            Circle()
                                .stroke(isAudioPlaying ? Color.accentColor : Color.gray, lineWidth: 3)
                        )
                    
                    Circle()
                        .fill(isAudioPlaying ? Color.accentColor : Color.gray)
                        .frame(width: 8, height: 8)
                }
                .position(x: geometry.size.width / 2,
                         y: CGFloat(1 - (ambientVolume / 100.0)) * geometry.size.height)
            }
            .frame(width: 60)
            .gesture(volumeDragGesture(in: geometry.size.height))
        }
        .frame(width: 60, height: 200)
    }
    
    private func volumeDragGesture(in height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Only allow volume changes if audio is playing
                guard isAudioPlaying else { return }
                
                let clampedY = max(0, min(value.location.y, height))
                let percent = 1.0 - (clampedY / height)
                let newValue = Float(percent * 100.0)
                ambientVolume = max(0.0, min(100.0, newValue))
                updateAmbientVolume(ambientVolume)
            }
    }
}
