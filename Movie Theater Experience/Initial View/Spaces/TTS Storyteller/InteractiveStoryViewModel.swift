//
//  InteractiveStoryViewModel.swift
//  Movie Theater Experience
//
//  Created by Gemini on 6/23/25.
//  Updated 6/27/25
//   - Fixed volume publisher logic
//

import Foundation
import AVFoundation
import Combine
import QuartzCore

@MainActor
class InteractiveStoryViewModel: ObservableObject {

    // MARK: - Session
    enum SessionState { case playing, interacting }
    @Published private(set) var sessionState: SessionState = .playing

    // MARK: - Player state
    @Published private(set) var isVideoPlaying = false
    @Published private(set) var isAudioPlaying = false
    @Published var isVideoMuted = false
    
    // MARK: - Volume & Scrubber
    @Published var volume: Double = 1.0 // This is updated by the slider
    @Published var audioCurrentTime: Double = 0
    @Published private(set) var audioDuration: Double = 1.0

    // MARK: - Interaction State
    @Published var isMicMuted = true // Default to muted
    var textDraft = ""

    // MARK: - Waveform
    private let barCount = 128
    @Published private(set) var audioLevels: [Float]
    
    let webSocketURL = "wss://storyteller-457201302256.us-east5.run.app/ws"

    // MARK: - Services
    private(set) var videoPlayer = AVPlayer()
    private(set) var narrationAudioService = StorytellerAudioService()
    private(set) lazy var liveStorytellerService: LiveStorytellerService = {
        let service = LiveStorytellerService()
        // Configure the service with the voice and instructions from the story model.
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



    // MARK: - Init -----------------------------------------------------------
    init(story: Story) {
        self.story = story
        self.audioLevels = [Float](repeating: 0, count: barCount)

        setupAudioSession()
        loadNarrationTrack()
        loadCurrentVideo()
        startDisplayLink()

        // --- Combine Subscribers for State Management ---
        
        // Bind video player status to isVideoPlaying
        videoPlayer.publisher(for: \.timeControlStatus)
            .map { $0 == .playing }
            .receive(on: DispatchQueue.main)
            .assign(to: &$isVideoPlaying)

        // 💡💡💡 **THIS IS THE FIX** 💡💡💡
        // This subscriber acts as the "glue". Whenever the `volume` property
        // changes (because you moved the slider), this code runs and updates
        // the volume on both AVPlayer instances.
        $volume
            .sink { [weak self] newVolume in
                self?.videoPlayer.volume = Float(newVolume)
                self?.narrationAudioService.player.volume = Float(newVolume)
            }
            .store(in: &cancellables)
    }

    // MARK: - Controls -------------------------------------------------------
    func playPauseVideoToggle() {
        videoPlayer.timeControlStatus == .playing ? videoPlayer.pause()
                                                  : videoPlayer.play()
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
    
    func skipToInteraction() {
        transitionToInteraction()
    }

    func toggleVideoMute() {
        isVideoMuted.toggle()
        videoPlayer.isMuted = isVideoMuted
    }

    // MARK: - Teardown
    func cleanup() {
        videoPlayer.pause()
        narrationAudioService.stop()        
        narrationAudioService.player.pause()
        stopDisplayLink()
        liveStorytellerService.disconnect()
        if let tok = timeObserverToken {
            narrationAudioService.player.removeTimeObserver(tok)
        }
    }
    
    private func loadNarrationTrack() {
        guard let url = story.audioURL else { return }

        // This part remains the same, it kicks off the asynchronous loading
        narrationAudioService.loadMedia(from: url)
        setupAudioPlayerStateObserver()

        let player = narrationAudioService.player

        // --- ENHANCED, ROBUST DURATION AND TIME OBSERVER LOGIC ---

        // This new publisher chain waits for the player's item to be ready.
        player.publisher(for: \.currentItem)
            .compactMap { $0 } // 1. Wait for a non-nil AVPlayerItem to be set
            .flatMap { item in
                // 2. Once we have an item, wait for its status to be .readyToPlay
                item.publisher(for: \.status)
                    .filter { $0 == .readyToPlay }
                    .map { _ in item } // 3. Pass the ready item along
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] readyItem in
                guard let self = self else { return }

                // 4. NOW the item is ready. Get the duration.
                let durationSeconds = readyItem.duration.seconds
                if durationSeconds.isFinite && durationSeconds > 0 {
                    self.audioDuration = durationSeconds
                }

                // 5. It's also safe to add the periodic time observer now.
                //    Remove any old observer first to prevent duplicates.
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

    private func loadCurrentVideo() {
        guard let url = URL(string: story.videos[currentVideoIndex]) else { return }
        videoPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: videoPlayer.currentItem)
            .sink { [weak self] _ in self?.videoPlayer.pause() }
            .store(in: &cancellables)
    }

    private func transitionToInteraction() {
        videoPlayer.pause()
        narrationAudioService.player.pause()
        
        // **KEY CHANGE 2**: The service is already configured. Just tell it to connect.
        liveStorytellerService.connectAndStart(urlString: webSocketURL)
        liveStorytellerService.setMic(active: false)
        
        sessionState = .interacting
    }
    

    // MARK: - Waveform engine -----------------------------------------------
    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateWaveform))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateWaveform() {
        // 1. Pick the right source
        let spec = (sessionState == .playing)
                 ? narrationAudioService.getSpectrum()
                 : liveStorytellerService.getSpectrum()

        // 2. Keep our local buffer in sync with the source length
        if audioLevels.count != spec.count {
            if audioLevels.count < spec.count {
                // grow: pad with zeros
                audioLevels += Array(repeating: 0, count: spec.count - audioLevels.count)
            } else {
                // shrink: drop the excess
                audioLevels.removeLast(audioLevels.count - spec.count)
            }
        }

        // 3. Smooth-update only up to the shortest length
        let count  = min(audioLevels.count, spec.count)
        let decay: Float = 0.75

        for i in 0..<count {
            let target = spec[i]
            audioLevels[i] = audioLevels[i] * decay + target * (1 - decay)
        }
    }

    // MARK: - Audio-player KVO ----------------------------------------------
    private func setupAudioPlayerStateObserver() {
        narrationAudioService.player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self, !self.isScrubbing else { return }
                self.isAudioPlaying = (status == .playing)
            }
            .store(in: &cancellables)
    }

    // MARK: - AVAudioSession -------------------------------------------------
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession error:", error)
        }
    }
    
    // MARK: - Interaction helpers ----------------------------------------------
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
        liveStorytellerService.disconnect()
        sessionState = .playing
    }
    
    func increaseVolume() {
        // Increase volume by 10%, capping at the max of 1.0
        volume = min(volume + 0.1, 1.0)
    }

    func decreaseVolume() {
        // Decrease volume by 10%, stopping at the min of 0.0
        volume = max(volume - 0.1, 0.0)
    }
    
}
