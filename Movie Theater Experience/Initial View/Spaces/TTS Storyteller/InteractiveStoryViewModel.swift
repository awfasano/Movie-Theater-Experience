//
//  InteractiveStoryViewModel.swift
//  Movie Theater Experience
//
//  Updated to include transcript functionality
//

import Foundation
import AVFoundation
import Combine
import QuartzCore

// MARK: - Transcript Model
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
    private(set) lazy var liveStorytellerService: LiveStorytellerService = {
        let service = LiveStorytellerService()
        service.configure(
            voice: self.story.voice,
            instruction: self.story.instructions
        )
        return service
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
        setupAudioSession()
        loadCurrentVideo()
        loadNarrationTrack()
        startDisplayLink()
        
        setupVolumeBinding()
        setupVideoPlayerStateObserver()
        
        // Request microphone permission early for visionOS
        AVAudioApplication.requestRecordPermission { granted in
            print("Microphone permission: \(granted)")
        }
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
        if sessionState == .interacting {
            //liveStorytellerService.handleTextFieldFocus(isFocused: isFocused)
        }
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
                let readyPublisher = item.publisher(for: \.status).filter { $0 == .readyToPlay }.map { _ in item.duration.seconds }
                return Publishers.CombineLatest(bufferingPublisher, readyPublisher)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (isBuffering, duration) in
                guard let self = self else { return }
                self.isNarrationBuffering = isBuffering
                if duration.isFinite && duration > 0 { self.audioDuration = duration }
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
    
    func skipToInteraction() {
        // Cancel any previous interaction listeners to prevent conflicts
        interactionCancellables.removeAll()
        
        // CRITICAL: Stop and clean up narration audio service FIRST
        narrationAudioService.stop()
        videoPlayer.pause()
        
        // Deactivate audio session before switching
        Task {
            do {
                // First deactivate the current session
                try AVAudioSession.sharedInstance().setActive(false)
                
                // Wait for cleanup to complete
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                await MainActor.run {
                    // Set UI state
                    self.sessionState = .connecting
                    self.errorMessage = ""
                    self.showingError = false
                    
                    // Set up connection status listener
                    self.liveStorytellerService.$status
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] status in
                            self?.handleConnectionStatus(status)
                        }
                        .store(in: &self.interactionCancellables)
                    
                    // Start connection (this will setup audio session for playAndRecord)
                    self.liveStorytellerService.connectAndStart(urlString: self.webSocketURL)
                }
            } catch {
                print("[ViewModel] Failed to deactivate audio session: \(error)")
                // Still try to proceed
                await MainActor.run {
                    self.sessionState = .connecting
                    self.liveStorytellerService.connectAndStart(urlString: self.webSocketURL)
                }
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
            setupAudioSession()
        case .permissionDenied:
            errorMessage = "Microphone permission was denied. You can use text chat."
            showingError = true
            if sessionState == .connecting {
                sessionState = .interacting
            }
        default:
            break
        }
    }

    func returnToStory() {
        // Cancel listeners before disconnecting
        interactionCancellables.removeAll()
        
        // Ensure mic is off before disconnecting
        liveStorytellerService.setMic(active: false)
        
        // Disconnect with full cleanup
        liveStorytellerService.disconnect(silent: false)
        
        Task {
            // Wait for LiveStorytellerService cleanup
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            
            do {
                // Deactivate audio session
                try AVAudioSession.sharedInstance().setActive(false)
                
                // Brief pause
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
                
                // Configure for story playback
                try AVAudioSession.sharedInstance().setCategory(.playback,
                                                                mode: .moviePlayback,
                                                                options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                
                print("[ViewModel] Audio session configured for story playback")
            } catch {
                print("[ViewModel] Audio session error during return to story: \(error)")
            }
            
            await MainActor.run {
                // Create a fresh instance of LiveStorytellerService for next time
                self.liveStorytellerService = LiveStorytellerService()
                self.liveStorytellerService.configure(
                    voice: self.story.voice,
                    instruction: self.story.instructions
                )
                
                self.sessionState = .playing
                self.showingError = false
                
                // Reload narration
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
        if audioLevels.count != spec.count { audioLevels = Array(repeating: 0, count: spec.count) }
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

    private func setupAudioSession() {
        Task.detached(priority: .utility) {
            do {
                // Choose category based on current state
                let category: AVAudioSession.Category
                let mode: AVAudioSession.Mode
                let options: AVAudioSession.CategoryOptions
                
                if await self.sessionState == .interacting {
                    category = .playAndRecord
                    mode = .voiceChat
                    options = [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
                } else {
                    category = .playback
                    mode = .moviePlayback
                    options = .mixWithOthers
                }
                
                try AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: options)
                try AVAudioSession.sharedInstance().setActive(true)
                
                print("[ViewModel] Audio session set: \(category.rawValue), mode: \(mode.rawValue)")
            } catch {
                print("[ViewModel] AVAudioSession error:", error)
            }
        }
    }
    
    func sendTextMessage() {
        guard sessionState == .interacting, !textDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        liveStorytellerService.send(text: textDraft)
        textDraft = ""
    }

    func toggleMic() {
        guard sessionState == .interacting, liveStorytellerService.isMicrophoneAvailable else { return }
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
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: newItem)
            .sink { [weak self] _ in self?.videoPlayer.pause() }
            .store(in: &playerCancellables)
        videoPlayer.replaceCurrentItem(with: newItem)
    }

    func cleanup() {
        // Stop all active audio players
        videoPlayer.pause()
        liveStorytellerService.disconnect(silent: true)
        
        // Reset audio session before stopping narration service
        setupAudioSession()
        narrationAudioService.stop()
        
        // Clean up remaining components
        stopDisplayLink()
        playerCancellables.removeAll()
        interactionCancellables.removeAll()

        if let tok = timeObserverToken {
            narrationAudioService.player.removeTimeObserver(tok)
            timeObserverToken = nil
        }
    }
}
