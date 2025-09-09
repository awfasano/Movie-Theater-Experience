//
//  InteractiveStoryViewModel.swift
//  Movie Theater Experience
//
//  Updated to improve AVAudioSession management during state transitions.
//

import Foundation
import AVFoundation
import Combine
import QuartzCore

// MARK: - Transcript Model (No changes)
struct TranscriptMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let text: String
    let timestamp: Date
    
    enum MessageRole {
        case user
        case assistant
    }
}

@MainActor
class InteractiveStoryViewModel: ObservableObject {
    
    // MARK: - Session
    @Published private(set) var sessionState: SessionState = .playing

    // MARK: - Player state
    @Published private(set) var isVideoPlaying = false
    @Published private(set) var isAudioPlaying = false
    @Published var isVideoMuted = false
    @Published private(set) var isNarrationBuffering = false
    @Published private(set) var isVideoBuffering = false
    enum SessionState { case playing, interacting, connecting, disconnected }

    // MARK: - Volume & Scrubber
    @Published var volume: Double = 1.0
    @Published var audioCurrentTime: Double = 0
    @Published private(set) var audioDuration: Double = 1.0
    
    // MARK: - Interaction State
    @Published var isMicMuted = true
    @Published var textDraft = ""

    @Published var errorMessage: String = ""
    @Published var showingError: Bool = false
    @Published var isTextFieldFocused = false

    
    // MARK: - Waveform
    private let barCount = 128
    @Published private(set) var audioLevels: [Float]
    
    let webSocketURL = "wss://storyteller-457201302256.us-east5.run.app"
    
    

    // MARK: - Services
    private(set) var videoPlayer = AVPlayer()
    private(set) var narrationAudioService = StorytellerAudioService()
    // Lazy initialization ensures configuration happens only when needed.
    private(set) lazy var liveStorytellerService: LiveStorytellerService = {
        createLiveStorytellerService()
    }()

    // MARK: - Private
    let story: Story
    private var currentVideoIndex = 0
    private var playerCancellables = Set<AnyCancellable>()
    private var interactionCancellables = Set<AnyCancellable>()
    private var displayLink: CADisplayLink?
    private var timeObserverToken: Any?
    private var isScrubbing = false
    private var wasPlayingBeforeScrub = false
    
    // MARK: - Init
    init(story: Story) {
        self.story = story
        self.audioLevels = [Float](repeating: 0, count: barCount)
    }
    
    @MainActor
    func prepare() async {
        // Configure the session for initial playback
        await configureAudioSessionForPlayback()
        loadCurrentVideo()
        loadNarrationTrack()
        startDisplayLink()
        
        setupVolumeBinding()
        setupVideoPlayerStateObserver()
        
        // Request microphone permission early
        AVAudioApplication.requestRecordPermission { granted in
            print("Microphone permission: \(granted)")
        }
    }
    
    // Helper to create and configure the Live service
    private func createLiveStorytellerService() -> LiveStorytellerService {
        let service = LiveStorytellerService()
        service.configure(
            voice: self.story.voice,
            instruction: self.story.instructions
        )
        return service
    }
    
    private func setupVolumeBinding() {
        $volume
            .sink { [weak self] vol in
                self?.videoPlayer.volume = Float(vol)
                self?.narrationAudioService.player.volume = Float(vol)
            }
            .store(in: &playerCancellables)
    }
    
    func handleTextFieldFocusChange(_ isFocused: Bool) {
        isTextFieldFocused = isFocused
    }
    
    private func setupVideoPlayerStateObserver() {
        videoPlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isVideoPlaying = (status == .playing)
            }
            .store(in: &playerCancellables)
        
        videoPlayer.publisher(for: \.currentItem?.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .map { $0 ?? false }
            .assign(to: &$isVideoBuffering)
    }

    // MARK: - Controls
    func playPauseVideoToggle() {
        videoPlayer.timeControlStatus == .playing ? videoPlayer.pause() : videoPlayer.play()
    }
    
    func playPauseAudioToggle() {
        let p = narrationAudioService.player
        p.timeControlStatus == .playing ? p.pause() : p.play()
    }
    
    func retryConnection() {
        skipToInteraction()
    }

    func audioScrubbingChanged(isEditing: Bool) {
        isScrubbing = isEditing
        let player = narrationAudioService.player
        if isEditing {
            wasPlayingBeforeScrub = (player.timeControlStatus == .playing)
            player.pause()
        } else {
            seekAudio(to: audioCurrentTime)
            if wasPlayingBeforeScrub { player.play() }
        }
    }
    
    func seekAudio(to sec: Double) {
        narrationAudioService.player.seek(to: CMTime(seconds: sec, preferredTimescale: 600))
    }

    func replayCurrentVideo() {
        videoPlayer.seek(to: .zero)
        if videoPlayer.timeControlStatus != .playing { videoPlayer.play() }
    }
    
    func previousVideo() {
        guard currentVideoIndex > 0 else { return }
        currentVideoIndex -= 1
        loadCurrentVideo()
    }
    
    func nextVideo() {
        guard currentVideoIndex < story.videos.count - 1 else { return }
        currentVideoIndex += 1
        loadCurrentVideo()
    }
    
    func toggleVideoMute() {
        isVideoMuted.toggle()
        videoPlayer.isMuted = isVideoMuted
    }
    
    private func loadNarrationTrack() {
        guard let url = story.audioURL else { return }
        isNarrationBuffering = true
        narrationAudioService.loadMedia(from: url)
        setupAudioPlayerStateObserver()

        let player = narrationAudioService.player

        player.publisher(for: \.currentItem)
            .compactMap { $0 }
            .flatMap { item in
                let bufferingPublisher = item.publisher(for: \.isPlaybackBufferEmpty).map { $0 }
                // Ensure we only proceed when status is readyToPlay
                let readyPublisher = item.publisher(for: \.status)
                    .filter { $0 == .readyToPlay }
                    .map { _ in item.duration.seconds }
                    // Use prefix(1) to ensure we only capture the duration once when ready
                    .prefix(1)
                
                return Publishers.CombineLatest(bufferingPublisher, readyPublisher)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (isBuffering, duration) in
                guard let self = self else { return }
                self.isNarrationBuffering = isBuffering
                if duration.isFinite && duration > 0 {
                    self.audioDuration = duration
                }
                // Setup time observer only once
                if self.timeObserverToken == nil {
                    self.timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                        guard let self = self, !self.isScrubbing else { return }
                        self.audioCurrentTime = time.seconds
                    }
                }
            }
            .store(in: &playerCancellables)
    }

    // MARK: - Interaction Flow
    
    // REVISED: Simplified transition logic.
    func skipToInteraction() {
        // Cancel any previous interaction listeners
        interactionCancellables.removeAll()
        
        // 1. Stop current playback systems
        narrationAudioService.stop()
        videoPlayer.pause()
        
        // Set UI state immediately
        self.sessionState = .connecting
        self.errorMessage = ""
        self.showingError = false

        // 2. Wait briefly for the narration service (AVPlayer) to release resources.
        Task {
            // A short delay (e.g., 100ms) helps ensure AVPlayer is quiet before switching modes.
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            await MainActor.run {
                // 3. Set up connection status listener
                self.liveStorytellerService.$status
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        self?.handleConnectionStatus(status)
                    }
                    .store(in: &self.interactionCancellables)
                
                // 4. Start connection.
                // The LiveStorytellerService is now responsible for configuring
                // the AVAudioSession to .playAndRecord and activating it.
                // We do NOT manually deactivate the session here, as it causes errors.
                self.liveStorytellerService.connectAndStart(urlString: self.webSocketURL)
            }
        }
    }
    
    private func handleConnectionStatus(_ status: LiveStorytellerService.Status) {
        switch status {
        case .connected:
            if sessionState == .connecting {
                sessionState = .interacting
            }
        case .error(let message):
            errorMessage = "Connection lost: \(message)"
            sessionState = .disconnected
            // If connection fails, revert audio session configuration
            Task { await configureAudioSessionForPlayback() }
        case .permissionDenied:
            // If permission was denied, we might already be connected (for text)
            // or still connecting.
            errorMessage = "Microphone permission was denied. You can use text chat."
            showingError = true
            // Allow interaction (text-only)
            if sessionState == .connecting {
                sessionState = .interacting
            }
        default:
            break
        }
    }

    // REVISED: Improved synchronization and session reconfiguration.
    func returnToStory() {
        interactionCancellables.removeAll()
        
        // 1. Ensure mic is off and disconnect.
        liveStorytellerService.setMic(active: false)
        // The LiveStorytellerService is responsible for deactivating the session during its disconnect.
        liveStorytellerService.disconnect(silent: false)
        
        Task {
            // 2. Wait for LiveStorytellerService cleanup and session deactivation.
            // This delay is crucial to ensure the session is fully released (setActive(false))
            // before reconfiguring it for playback.
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // 3. Configure session back for story playback.
            await configureAudioSessionForPlayback()
            
            await MainActor.run {
                // 4. Create a fresh instance of LiveStorytellerService for next time
                // This ensures a clean state for the next interaction.
                self.liveStorytellerService = createLiveStorytellerService()
                
                self.sessionState = .playing
                self.showingError = false
                
                // 5. Reload narration
                self.loadNarrationTrack()
            }
        }
    }


    // MARK: - Lifecycle & Helpers
    
    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateWaveform))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateWaveform() {
        let spec = (sessionState == .playing)
            ? narrationAudioService.getSpectrum()
            : liveStorytellerService.getSpectrum()
        
        // Ensure array sizes match before updating
        if audioLevels.count != spec.count {
            audioLevels = Array(repeating: 0, count: spec.count)
        }
        
        // Apply decay for smoothing
        let decay: Float = 0.75
        for i in 0..<spec.count {
            audioLevels[i] = audioLevels[i] * decay + spec[i] * (1 - decay)
        }
    }

    private func setupAudioPlayerStateObserver() {
        narrationAudioService.player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self, !self.isScrubbing else { return }
                self.isAudioPlaying = (status == .playing)
            }
            .store(in: &playerCancellables)
    }

    // REVISED: Centralized configuration for Playback mode.
    // This function is called when starting the view and when returning from interaction.
    private func configureAudioSessionForPlayback() async {
        // Use a detached task for session configuration as it can block.
        await Task.detached(priority: .userInitiated) {
            do {
                // Configure for standard media playback
                try AVAudioSession.sharedInstance().setCategory(.playback,
                                                                mode: .moviePlayback,
                                                                options: [.mixWithOthers])
                // Activate the session with the new configuration.
                try AVAudioSession.sharedInstance().setActive(true)
                
                print("[ViewModel] Audio session configured for story playback")
            } catch {
                // Log errors if configuration fails (e.g., due to priority conflicts).
                print("[ViewModel] Audio session error during configuration for playback: \(error)")
            }
        }.value
    }
        
    func sendTextMessage() {
        // Allow sending if interacting or still connecting (to buffer the message)
        guard sessionState == .interacting || sessionState == .connecting, !textDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        // Send the text via the service
        liveStorytellerService.send(text: textDraft)
        
        // Clear the draft immediately for better UX
        textDraft = ""
    }

    func toggleMic() {
        // Check status and availability before toggling
        guard (sessionState == .interacting || sessionState == .connecting), liveStorytellerService.isMicrophoneAvailable else { return }
        isMicMuted.toggle()
        liveStorytellerService.setMic(active: !isMicMuted)
    }
    
    func increaseVolume() {
        volume = min(volume + 0.1, 1.0)
    }

    func decreaseVolume() {
        volume = max(volume - 0.1, 0.0)
    }
    
    private func loadCurrentVideo() {
        guard currentVideoIndex < story.videos.count, let url = URL(string: story.videos[currentVideoIndex]) else { return }
        isVideoBuffering = true
        let newItem = AVPlayerItem(asset: AVURLAsset(url: url))
        // Observe when the video finishes playing
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: newItem)
            .sink { [weak self] _ in self?.videoPlayer.pause() }
            .store(in: &playerCancellables)
        videoPlayer.replaceCurrentItem(with: newItem)
    }

    func cleanup() {
        // Stop all active audio/video players
        videoPlayer.pause()
        // Disconnect live service (this also deactivates the session)
        liveStorytellerService.disconnect(silent: true)
        
        // Stop narration service
        narrationAudioService.stop()
        
        // Clean up remaining components
        stopDisplayLink()
        playerCancellables.removeAll()
        interactionCancellables.removeAll()

        if let tok = timeObserverToken {
            narrationAudioService.player.removeTimeObserver(tok)
            timeObserverToken = nil
        }
        
        // Reset audio session to default (playback) when leaving the view
        Task { await configureAudioSessionForPlayback() }
    }
}
