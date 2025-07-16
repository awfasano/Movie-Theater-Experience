//
//  InteractiveStoryViewModel.swift
//  Movie Theater Experience
//
//  Updated to fix WebSocket connection stuttering
//

import Foundation
import AVFoundation
import Combine
import QuartzCore

@MainActor
class InteractiveStoryViewModel: ObservableObject {
    
    // MARK: - Session
    enum SessionState { case playing, interacting, connecting }
    @Published private(set) var sessionState: SessionState = .playing

    // MARK: - Player state
    @Published private(set) var isVideoPlaying = false
    @Published private(set) var isAudioPlaying = false
    @Published var isVideoMuted = false
    
    // MARK: - Volume & Scrubber
    @Published var volume: Double = 1.0
    @Published var audioCurrentTime: Double = 0
    @Published private(set) var audioDuration: Double = 1.0
    @Published private(set) var liveTranscript: String = ""

    // MARK: - Interaction State
    @Published var isMicMuted = true
    var textDraft = ""

    @Published var errorMessage: String = ""
    @Published var showingError: Bool = false
    
    // MARK: - Waveform
    private let barCount = 128
    @Published private(set) var audioLevels: [Float]
    
    let webSocketURL = "wss://storyteller-457201302256.us-east5.run.app/ws"

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
    private var cancellables = Set<AnyCancellable>()
    private var displayLink: CADisplayLink?
    private var timeObserverToken: Any?
    private var isScrubbing = false
    private var wasPlayingBeforeScrub = false
    
    // MARK: - Storyteller Configuration
    var storytellerVoice = "Zephyr"
    var storytellerInstruction = "You are a helpful and creative storyteller."

    // MARK: - Init
    init(story: Story) {
        self.story = story
        self.audioLevels = [Float](repeating: 0, count: barCount)
    }
    
    @MainActor
    func prepare() async {
        setupAudioSession()
        await loadNarrationTrackAsync()
        loadCurrentVideo()
        startDisplayLink()
        setupVolumeBinding()
        setupVideoPlayerStateObserver()
    }
    
    private func setupVolumeBinding() {
        $volume
            .sink { [weak self] vol in
                self?.videoPlayer.volume = Float(vol)
                self?.narrationAudioService.player.volume = Float(vol)
            }
            .store(in: &cancellables)
    }
    
    private func setupVideoPlayerStateObserver() {
        videoPlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isVideoPlaying = (status == .playing)
            }
            .store(in: &cancellables)
    }

    // MARK: - Controls
    func playPauseVideoToggle() {
        videoPlayer.timeControlStatus == .playing ? videoPlayer.pause() : videoPlayer.play()
    }
    
    func playPauseAudioToggle() {
        let p = narrationAudioService.player
        p.timeControlStatus == .playing ? p.pause() : p.play()
    }

    func audioScrubbingChanged(isEditing: Bool) {
        isScrubbing = isEditing
        if isEditing {
            wasPlayingBeforeScrub = isAudioPlaying
            narrationAudioService.player.pause()
        } else {
            seekAudio(to: audioCurrentTime)
            if wasPlayingBeforeScrub { narrationAudioService.player.play() }
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
        if videoPlayer.timeControlStatus == .playing { videoPlayer.play() }
    }
    
    func nextVideo() {
        guard currentVideoIndex < story.videos.count - 1 else { return }
        currentVideoIndex += 1
        loadCurrentVideo()
        if videoPlayer.timeControlStatus == .playing { videoPlayer.play() }
    }
    
    func toggleVideoMute() {
        isVideoMuted.toggle()
        videoPlayer.isMuted = isVideoMuted
    }
    
    private func loadNarrationTrackAsync() async {
        guard let url = story.audioURL else { return }

        let asset = AVURLAsset(url: url)
        _ = try? await asset.load(.duration)

        await MainActor.run {
            narrationAudioService.loadAsset(asset)
            setupAudioPlayerStateObserver()
            audioDuration = asset.duration.seconds
        }
    }
    
    private func loadNarrationTrack() {
        guard let url = story.audioURL else { return }

        narrationAudioService.loadMedia(from: url)
        setupAudioPlayerStateObserver()

        let player = narrationAudioService.player

        player.publisher(for: \.currentItem)
            .compactMap { $0 }
            .flatMap { item in
                item.publisher(for: \.status)
                    .filter { $0 == .readyToPlay }
                    .map { _ in item }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] readyItem in
                guard let self = self else { return }

                let durationSeconds = readyItem.duration.seconds
                if durationSeconds.isFinite && durationSeconds > 0 {
                    self.audioDuration = durationSeconds
                }

                if let existingToken = self.timeObserverToken {
                    player.removeTimeObserver(existingToken)
                }
                
                self.timeObserverToken = player.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                    queue: .main
                ) { [weak self] time in
                    guard let self = self, !self.isScrubbing else { return }
                    self.audioCurrentTime = time.seconds
                }
            }
            .store(in: &cancellables)
    }

    func skipToInteraction() {
        // Start the transition immediately but show connecting state
        sessionState = .connecting
        
        // Pause media immediately to provide instant feedback
        videoPlayer.pause()
        narrationAudioService.player.pause()
        
        // Clear any previous errors
        errorMessage = ""
        showingError = false
        
        // Configure the service
        liveStorytellerService.configure(
            voice: story.voice,
            instruction: story.instructions
        )
        
        // Setup monitoring before connection
        setupConnectionMonitoring()
        
        // Connect asynchronously to avoid blocking the main thread
        Task {
            await connectToStorytellerService()
        }
    }
    
    private func setupConnectionMonitoring() {
        liveStorytellerService.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                
                switch status {
                case .connected:
                    print("✅ Connected to storyteller service")
                    // Only transition to interacting once actually connected
                    if self.sessionState == .connecting {
                        self.sessionState = .interacting
                    }
                    
                case .error(let message):
                    self.errorMessage = "Audio connection failed: \(message)"
                    self.showingError = true
                    // Return to playing state on error
                    if self.sessionState == .connecting {
                        self.sessionState = .playing
                    }
                    
                case .permissionDenied:
                    self.errorMessage = "Microphone permission is required for interaction. Please enable it in Settings."
                    self.showingError = true
                    if self.sessionState == .connecting {
                        self.sessionState = .playing
                    }
                    
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    private func connectToStorytellerService() async {
        // Perform the actual connection on a background queue
        await withCheckedContinuation { continuation in
            Task.detached {
                // This runs on a background thread
                await MainActor.run {
                    self.liveStorytellerService.connectAndStart(urlString: self.webSocketURL)
                    self.liveStorytellerService.setMic(active: false)
                }
                continuation.resume()
            }
        }
    }
    
    func retryConnection() {
        guard sessionState == .interacting || sessionState == .connecting else { return }
        
        errorMessage = ""
        showingError = false
        sessionState = .connecting
        
        liveStorytellerService.disconnect()
        
        // Retry connection after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await connectToStorytellerService()
        }
    }

    // MARK: - Waveform engine
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

        if audioLevels.count != spec.count {
            if audioLevels.count < spec.count {
                audioLevels += Array(repeating: 0, count: spec.count - audioLevels.count)
            } else {
                audioLevels.removeLast(audioLevels.count - spec.count)
            }
        }

        let count = min(audioLevels.count, spec.count)
        let decay: Float = 0.75

        for i in 0..<count {
            let target = spec[i]
            audioLevels[i] = audioLevels[i] * decay + target * (1 - decay)
        }
    }

    // MARK: - Audio-player KVO
    private func setupAudioPlayerStateObserver() {
        narrationAudioService.player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self, !self.isScrubbing else { return }
                self.isAudioPlaying = (status == .playing)
            }
            .store(in: &cancellables)
    }

    // MARK: - AVAudioSession
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession error:", error)
        }
    }
    
    // MARK: - Interaction helpers
    func sendTextMessage() {
        guard sessionState == .interacting, !textDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        liveStorytellerService.send(text: textDraft)
        textDraft = ""
    }

    func toggleMic() {
        guard sessionState == .interacting else { return }
        isMicMuted.toggle()
        liveStorytellerService.setMic(active: !isMicMuted)
    }

    func returnToStory() {
        liveStorytellerService.disconnect(silent: true)
        cancellables.removeAll()
        sessionState = .playing
        showingError = false
    }
    
    func increaseVolume() {
        volume = min(volume + 0.1, 1.0)
    }

    func decreaseVolume() {
        volume = max(volume - 0.1, 0.0)
    }
    
    // MARK: - Video Loading
    private func loadCurrentVideo() {
        // 1. Cancel previous observers to prevent leaks
        cancellables.removeAll()
        
        guard let url = URL(string: story.videos[currentVideoIndex]) else { return }

        // 2. Start a background Task to load the asset
        Task {
            do {
                let asset = AVURLAsset(url: url)
                
                // 3. Asynchronously load the 'playable' property. This does network I/O in the background.
                let isPlayable = try await asset.load(.isPlayable)

                if isPlayable {
                    let newItem = AVPlayerItem(asset: asset)
                    
                    // 4. Switch back to the main thread to update the UI
                    await MainActor.run {
                        self.videoPlayer.replaceCurrentItem(with: newItem)
                        
                        // Re-attach the end-time observer for the new item
                        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: self.videoPlayer.currentItem)
                            .sink { [weak self] _ in self?.videoPlayer.pause() }
                            .store(in: &self.cancellables)
                    }
                } else {
                    print("Error: Video at \(url) is not playable.")
                    // You might want to show an error to the user here.
                }
            } catch {
                print("Error loading video asset: \(error)")
            }
        }
    }

    // MARK: - Teardown
    func cleanup() {
        videoPlayer.pause()
        narrationAudioService.stop()
        narrationAudioService.player.pause()
        stopDisplayLink()

        liveStorytellerService.disconnect(silent: true)
        cancellables.removeAll()

        if let tok = timeObserverToken {
            narrationAudioService.player.removeTimeObserver(tok)
            timeObserverToken = nil
        }

        errorMessage = ""
        showingError = false
    }
}
