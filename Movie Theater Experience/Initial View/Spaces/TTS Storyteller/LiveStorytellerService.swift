//
//  LiveStorytellerService.swift
//  Movie Theater Experience
//
//  Fixed to match the web client's message format
//

import Foundation
import AVFoundation
import Accelerate
import Combine

@MainActor
final class LiveStorytellerService: ObservableObject {
    
    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case permissionDenied
        case error(String)
    }
    
    @Published private(set) var status: Status = .idle
    @Published private(set) var isMicrophoneAvailable: Bool = false
    @Published private(set) var transcripts: [TranscriptEntry] = []
    private var isSettingUpMicrophone = false
    private var hasSetupMicrophone = false
    
    struct TranscriptEntry: Identifiable {
        let id = UUID()
        let role: String  // "user" or "model"
        let text: String
        let isFinal: Bool
    }
    
    @Published private(set) var isSendingAudio = false
    @Published private(set) var isSendingText = false
    @Published private(set) var isWaitingForResponse = false
    @Published private(set) var isMicMuted: Bool = true  // Add this line

    
    // Add a property to track if we've sent something and are waiting
    private var lastSentMessageTime: Date?
    
    // WebSocket connection
    private var webSocketTask: URLSessionWebSocketTask?
    private var voice: String = "Puck"
    private var instruction: String = "You are a helpful storyteller."
    
    // Audio components
    private let audioSession = AVAudioSession.sharedInstance()
    private let audioEngine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()
    private var isConnecting = false
    private var isAudioEngineSetup = false
    private var setupTask: Task<Void, Never>?
    
    // Audio formats
    private let recordingFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!
    
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24000,
        channels: 1,
        interleaved: true
    )!
    
    // Audio converters
    private var micInputConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    
    // Audio buffering
    private var audioBufferQueue = [AVAudioPCMBuffer]()
    private let pcmQueue = DispatchQueue(label: "com.storyteller.pcmQueue")
    private var isPlayingFromQueue = false
    
    private var hasStartedPlayback = false
    private let audioBufferThreshold = 3 // Start playing after 3 chunks are buffered
    
    // Audio metering
    private var currentLevel: Float = 0
    private var latestSpectrum: [Float] = Array(repeating: 0, count: 128)
    
    func getCurrentLevel() -> Float { currentLevel }
    func getSpectrum() -> [Float] { latestSpectrum }
    
    // MARK: - Configuration
    
    func configure(voice: String, instruction: String) {
        self.voice = voice
        self.instruction = instruction
    }
    
    // MARK: - Connection Management
    
    func connectAndStart(urlString: String) {
        // Prevent multiple simultaneous connection attempts
        guard !isConnecting else {
            print("[LiveStoryteller] Connection already in progress, ignoring duplicate call")
            return
        }
        
        isConnecting = true
        
        // Cancel any existing setup task
        setupTask?.cancel()
        setupTask = nil
        
        checkMicrophonePermission { [weak self] hasPermission in
            guard let self = self else { return }
            
            if !hasPermission {
                self.status = .permissionDenied
                self.isMicrophoneAvailable = false
            }
            
            self.status = .connecting
            
            // Clean up any existing connection
            self.disconnect(silent: true)
            
            // Reset all flags
            self.isAudioEngineSetup = false
            self.isSettingUpMicrophone = false
            self.hasSetupMicrophone = false
            
            // Setup audio engine once
            self.setupTask = Task {
                await self.setupAudioEngineAsync()
            }
            
            // Setup WebSocket
            let wsURLString = urlString.replacingOccurrences(of: "https://", with: "wss://")
                .replacingOccurrences(of: "http://", with: "ws://")
            let fullURLString = wsURLString.hasSuffix("/live-chat") ? wsURLString : "\(wsURLString)/live-chat"
            
            guard let url = URL(string: fullURLString) else {
                self.status = .error("Invalid WebSocket URL")
                self.isConnecting = false
                return
            }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            
            self.webSocketTask = URLSession.shared.webSocketTask(with: request)
            self.webSocketTask?.resume()
            
            self.listenForMessages()
            
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                await self.sendConfiguration()
                self.isConnecting = false
            }
            
            self.startPingTimer()
        }
    }
    
    private func sendConfiguration() async {
        // Match the exact format the web client sends
        let config: [String: Any] = [
            "system_instruction": instruction,
            "voice_name": voice,
            "max_context_turns": 8
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: config, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            await MainActor.run {
                self.status = .error("Failed to create configuration")
            }
            return
        }
        
        print("[LiveStoryteller] Sending config: \(jsonString)")
        
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            Task { @MainActor in
                if let error = error {
                    self?.status = .error("Failed to send config: \(error.localizedDescription)")
                    print("[LiveStoryteller] Config send error: \(error)")
                } else {
                    // Wait for the server to be ready before marking as connected
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    self?.status = .connected
                    print("[LiveStoryteller] Successfully connected and configured")
                }
            }
        }
    }
    
    func disconnect(silent: Bool = false) {
        // Cancel any ongoing setup
        setupTask?.cancel()
        setupTask = nil
        
        // IMPORTANT: Reset ALL connection flags
        isConnecting = false
        isAudioEngineSetup = false
        isSettingUpMicrophone = false
        hasSetupMicrophone = false
        
        // Reset audio state
        hasStartedPlayback = false
        isSendingAudio = false
        isSendingText = false
        isWaitingForResponse = false
        
        // Clean up audio
        cleanupAudioEngine()
        
        // Close WebSocket
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        // Clear buffers
        pcmQueue.sync {
            audioBufferQueue.removeAll()
            isPlayingFromQueue = false
        }
        
        if !silent {
            status = .idle
            transcripts.removeAll()
        }
    }
    
    // MARK: - WebSocket Communication
    
    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.processMessage(message)
                self.listenForMessages() // Continue listening
                
            case .failure(let error):
                if (error as NSError).code != NSURLErrorCancelled {
                    Task { @MainActor in
                        self.status = .error("Connection lost: \(error.localizedDescription)")
                        print("[LiveStoryteller] WebSocket error: \(error)")
                    }
                }
            }
        }
    }
    
    private func processMessage(_ message: URLSessionWebSocketTask.Message) {
            switch message {
            case .string(let text):
                print("[LiveStoryteller] Received text message: \(text)")
                
                // Clear waiting state when we get a response
                Task { @MainActor in
                    self.isWaitingForResponse = false
                }
                
                // Handle JSON messages (transcripts)
                if let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if let type = json["type"] as? String, type == "transcript" {
                        if let role = json["role"] as? String,
                           let transcriptText = json["text"] as? String,
                           let isFinal = json["is_final"] as? Bool {
                            
                            Task { @MainActor in
                                // Clear waiting state if we're getting assistant responses
                                if role == "model" || role == "assistant" {
                                    self.isWaitingForResponse = false
                                }
                                
                                // Update or add transcript
                                if !isFinal {
                                    if let lastIndex = self.transcripts.lastIndex(where: { $0.role == role && !$0.isFinal }) {
                                        self.transcripts[lastIndex] = TranscriptEntry(role: role, text: transcriptText, isFinal: false)
                                    } else {
                                        self.transcripts.append(TranscriptEntry(role: role, text: transcriptText, isFinal: false))
                                    }
                                } else {
                                    if let lastIndex = self.transcripts.lastIndex(where: { $0.role == role && !$0.isFinal }) {
                                        self.transcripts[lastIndex] = TranscriptEntry(role: role, text: transcriptText, isFinal: true)
                                    } else {
                                        self.transcripts.append(TranscriptEntry(role: role, text: transcriptText, isFinal: true))
                                    }
                                }
                            }
                        }
                    }
                }
                
            case .data(let data):
                // Handle audio data - this means we're getting a response
                print("[LiveStoryteller] Received audio data: \(data.count) bytes")
                
                Task { @MainActor in
                    self.isWaitingForResponse = false
                }
                
                handleIncomingAudio(data)
                
            @unknown default:
                break
            }
        }
    
    func send(text: String) {
        guard status == .connected else {
            print("[LiveStoryteller] Cannot send - not connected (status: \(status))")
            return
        }
        
        // Show sending state
        isSendingText = true
        lastSentMessageTime = Date()
        
        let message: [String: Any] = [
            "type": "text",
            "data": text
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[LiveStoryteller] Failed to encode text message")
            isSendingText = false
            return
        }
        
        print("[LiveStoryteller] Sending text: \(jsonString)")
        
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            Task { @MainActor in
                self?.isSendingText = false
                if error != nil {
                    print("[LiveStoryteller] Failed to send text: \(error!)")
                } else {
                    print("[LiveStoryteller] Text sent successfully")
                    self?.isWaitingForResponse = true
                }
            }
        }
    }
    
    func clearWaitingState() {
        isWaitingForResponse = false
        isSendingAudio = false
        isSendingText = false
    }

    
    private func startPingTimer() {
        Task {
            while webSocketTask != nil {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                webSocketTask?.sendPing { error in
                    if let error = error {
                        print("[LiveStoryteller] Ping failed: \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Audio Setup
    
    private func diagnoseAudioSystem() {
        print("=== AUDIO SYSTEM DIAGNOSTICS ===")
        
        // Basic audio session info
        print("Audio Session:")
        print("  - Category: \(audioSession.category.rawValue)")
        print("  - Mode: \(audioSession.mode.rawValue)")
        print("  - Options: \(audioSession.categoryOptions.rawValue)")
        print("  - Input available: \(audioSession.isInputAvailable)")
        print("  - Input gain settable: \(audioSession.isInputGainSettable)")
        
        // Available inputs
        print("Available Audio Inputs:")
        let availableInputs = AVAudioSession.sharedInstance().availableInputs ?? []
        if availableInputs.isEmpty {
            print("  - NO INPUTS AVAILABLE")
        } else {
            for (index, input) in availableInputs.enumerated() {
                print("  - Input \(index): \(input.portName) (\(input.portType.rawValue))")
                print("    Channels: \(input.channels?.count ?? 0)")
                print("    UID: \(input.uid)")
            }
        }
        
        // Current route
        print("Current Audio Route:")
        let currentRoute = audioSession.currentRoute
        print("  - Inputs: \(currentRoute.inputs.count)")
        for (index, input) in currentRoute.inputs.enumerated() {
            print("    Input \(index): \(input.portName) (\(input.portType.rawValue))")
        }
        print("  - Outputs: \(currentRoute.outputs.count)")
        for (index, output) in currentRoute.outputs.enumerated() {
            print("    Output \(index): \(output.portName) (\(output.portType.rawValue))")
        }
        
        // Preferred input
        if let preferredInput = audioSession.preferredInput {
            print("Preferred Input: \(preferredInput.portName)")
        } else {
            print("Preferred Input: None set")
        }
        
        // Permission status
        let permission = AVAudioApplication.shared.recordPermission
        print("Record Permission: \(permission.rawValue)")
        
        // Audio engine status
        print("Audio Engine:")
        print("  - Is running: \(audioEngine.isRunning)")
        print("  - Input node format: \(audioEngine.inputNode.outputFormat(forBus: 0))")
        
        print("=== END DIAGNOSTICS ===")
    }
    
    private func setupMicrophoneSafely() {
        // Only proceed if not already setting up
        guard !isSettingUpMicrophone && !hasSetupMicrophone else {
            print("[Debug] Microphone setup already in progress or completed")
            return
        }
        
        setupMicrophoneWithRetriesSafe(maxRetries: 10)
    }

    
    
    // Replace the setupMicrophone() and related methods in LiveStorytellerService.swift with:

    private func setupMicrophoneWithRetriesSafe(maxRetries: Int = 10, currentRetry: Int = 0) {
        // Double-check flags
        guard !hasSetupMicrophone else {
            print("[Debug] Microphone already setup")
            return
        }
        
        guard !isSettingUpMicrophone else {
            print("[Debug] Microphone setup in progress")
            return
        }
        
        isSettingUpMicrophone = true
        
        print("[Debug] Microphone setup attempt \(currentRetry + 1) of \(maxRetries)")
        
        let permission = AVAudioApplication.shared.recordPermission
        guard permission == .granted else {
            print("[Debug] No microphone permission")
            isSettingUpMicrophone = false
            isMicrophoneAvailable = false
            return
        }
        
        guard audioEngine.isRunning else {
            print("[Debug] Audio engine not running")
            isSettingUpMicrophone = false
            if currentRetry < maxRetries - 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.setupMicrophoneWithRetriesSafe(maxRetries: maxRetries, currentRetry: currentRetry + 1)
                }
            }
            return
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        print("[Debug] Input format: \(inputFormat)")
        
        guard inputFormat.sampleRate > 0 else {
            print("[Debug] Invalid sample rate")
            isSettingUpMicrophone = false
            if currentRetry < maxRetries - 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.setupMicrophoneWithRetriesSafe(maxRetries: maxRetries, currentRetry: currentRetry + 1)
                }
            }
            return
        }
        
        // Create converter
        micInputConverter = AVAudioConverter(from: inputFormat, to: recordingFormat)
        guard micInputConverter != nil else {
            print("[Debug] Failed to create converter")
            isSettingUpMicrophone = false
            isMicrophoneAvailable = false
            return
        }
        
        // Install tap with careful error handling
        do {
            // Remove any existing tap first
            inputNode.removeTap(onBus: 0)
        } catch {
            // Ignore - no tap to remove
        }
        
        // Small delay to ensure removal is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            do {
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                    self?.processMicrophoneBuffer(buffer)
                }
                
                print("[Debug] Microphone tap installed!")
                self.hasSetupMicrophone = true
                self.isMicrophoneAvailable = true
                
            } catch {
                print("[Debug] Failed to install tap: \(error)")
                
                if currentRetry < maxRetries - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.setupMicrophoneWithRetriesSafe(maxRetries: maxRetries, currentRetry: currentRetry + 1)
                    }
                } else {
                    self.isMicrophoneAvailable = false
                }
            }
            
            self.isSettingUpMicrophone = false
        }
    }

    // Updated setupAudioEngine method:
    private func setupAudioEngineAsync() async {
        guard !isAudioEngineSetup else {
            print("[Debug] Audio engine already setup, skipping")
            return
        }
        
        isAudioEngineSetup = true
        
        await MainActor.run {
            self.cleanupAudioEngine()
        }
        
        do {
            // Configure audio session with echo cancellation for better quality
            try audioSession.setCategory(.playAndRecord,
                                        mode: .voiceChat,  // Use voiceChat mode for better echo cancellation
                                        options: [.defaultToSpeaker,
                                                .allowBluetooth,
                                                .mixWithOthers,
                                                .allowBluetoothA2DP])
            
            // Set preferred configuration
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.01)  // Slightly larger buffer for stability
            
            // Enable echo cancellation if available
            if audioSession.isInputGainSettable {
                try audioSession.setInputGain(0.8)  // Reduce input gain to prevent feedback
            }
            
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            
            // Wait for activation
            try await Task.sleep(nanoseconds: 500_000_000)
            
            await MainActor.run {
                self.audioEngine.attach(self.audioPlayer)
                self.audioEngine.connect(self.audioPlayer, to: self.audioEngine.mainMixerNode, format: nil)
                
                // Enable voice processing if available (echo cancellation, noise suppression)
                if self.audioEngine.inputNode.isVoiceProcessingBypassed {
                    self.audioEngine.inputNode.isVoiceProcessingBypassed = false
                }
                
                self.audioEngine.prepare()
            }
            
            try audioEngine.start()
            print("[Debug] Audio engine started successfully with voice processing")
            
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            await MainActor.run {
                self.setupMicrophoneSafely()
                self.setupOutputMeteringSafely()
            }
            
        } catch {
            print("[Audio] Engine setup failed: \(error)")
            await MainActor.run {
                self.isMicrophoneAvailable = false
                self.isAudioEngineSetup = false
            }
        }
    }
    
    // Add a method to handle text field focus changes:
    func handleTextFieldFocus(isFocused: Bool) {
        // Don't change audio session when text field is focused/unfocused
        // This prevents the audio glitches
        if isFocused {
            print("[Debug] Text field focused - maintaining audio session")
            // Optionally reduce mic gain slightly to prevent feedback
            if isMicrophoneAvailable && !isMicMuted {
                audioEngine.inputNode.volume = 0.8
            }
        } else {
            print("[Debug] Text field unfocused - restoring normal audio")
            if isMicrophoneAvailable && !isMicMuted {
                audioEngine.inputNode.volume = 1.0
            }
        }
    }
        

    // Add this helper method to force audio route refresh on visionOS:
    private func refreshAudioRoute() {
        do {
            // Deactivate and reactivate to force route refresh
            try audioSession.setActive(false)
            try audioSession.setActive(true)
            
            // Check for available inputs
            if let inputs = audioSession.availableInputs, !inputs.isEmpty {
                // Try to set the first available input as preferred
                try audioSession.setPreferredInput(inputs[0])
                print("[Debug] Set preferred input to: \(inputs[0].portName)")
            }
        } catch {
            print("[Debug] Failed to refresh audio route: \(error)")
        }
    }
    
    
    private func debugAudioSession() {
        print("[Debug] Audio Session Debug:")
        print("  - Category: \(audioSession.category)")
        print("  - Mode: \(audioSession.mode)")
        print("  - Options: \(audioSession.categoryOptions)")
        print("  - Input available: \(audioSession.isInputAvailable)")
        print("  - Input gain settable: \(audioSession.isInputGainSettable)")
        print("  - Record permission: \(AVAudioApplication.shared.recordPermission)")
        
        if let route = audioSession.currentRoute.inputs.first {
            print("  - Input route: \(route.portName) (\(route.portType))")
        } else {
            print("  - No input route found")
        }
        
        if let preferredInput = audioSession.preferredInput {
            print("  - Preferred input: \(preferredInput.portName)")
        } else {
            print("  - No preferred input set")
        }
    }

    
    private func cleanupAudioEngine() {
        // Reset all flags
        isAudioEngineSetup = false
        isSettingUpMicrophone = false
        hasSetupMicrophone = false
        
        // Stop engine first
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        audioPlayer.stop()
        
        // Remove all taps
        do { audioEngine.inputNode.removeTap(onBus: 0) } catch { }
        do { audioEngine.mainMixerNode.removeTap(onBus: 0) } catch { }
        
        // Reset converters and state
        micInputConverter = nil
        playbackConverter = nil
        isMicrophoneAvailable = false
        
        print("[Debug] Audio engine cleanup complete")
    }

        
        // Remove the old setupMicrophone method completely (not needed anymore)
    // Add this debugging code to setupMicrophone() in LiveStorytellerService.swift
    
    private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        // Don't process if muted
        guard !isMicMuted else { return }
        
        guard status == .connected,
              let converter = micInputConverter else { return }
        
        let outputFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * recordingFormat.sampleRate / buffer.format.sampleRate
        )
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: outputFrameCapacity) else { return }
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if error == nil, let data = outputBuffer.toData() {
            // Show that we're sending audio
            Task { @MainActor in
                self.isSendingAudio = true
                self.lastSentMessageTime = Date()
            }
            
            // Send raw PCM16 audio to server
            webSocketTask?.send(.data(data)) { [weak self] _ in
                Task { @MainActor in
                    // After sending, we're waiting for response
                    self?.isSendingAudio = false
                    self?.isWaitingForResponse = true
                }
            }
        }
    }
    
    private func handleIncomingAudio(_ data: Data) {
        // Temporarily reduce mic input to prevent feedback
        let previousMicVolume = audioEngine.inputNode.volume
        if !isMicMuted {
            audioEngine.inputNode.volume = 0.1  // Reduce to 10% during playback
        }
        
        guard let pcmBuffer = data.toPCMBuffer(format: playbackFormat) else { return }
        let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        if playbackConverter == nil {
            playbackConverter = AVAudioConverter(from: playbackFormat, to: outputFormat)
        }
        guard let converter = playbackConverter else { return }
        let outputFrameCapacity = AVAudioFrameCount(Double(pcmBuffer.frameLength) * outputFormat.sampleRate / pcmBuffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else { return }
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }

        if error == nil {
            pcmQueue.async {
                self.audioBufferQueue.append(outputBuffer)

                if !self.hasStartedPlayback && self.audioBufferQueue.count >= self.audioBufferThreshold {
                    Task { @MainActor in
                        self.hasStartedPlayback = true
                        self.playNextBuffer()
                    }
                }
            }
        }
    }


    private func playNextBuffer() {
        pcmQueue.async {
            guard !self.audioBufferQueue.isEmpty else {
                Task { @MainActor in
                    self.hasStartedPlayback = false
                    // Restore mic volume after all buffers are played
                    if !self.isMicMuted {
                        self.audioEngine.inputNode.volume = 1.0
                    }
                }
                return
            }

            let bufferToPlay = self.audioBufferQueue.removeFirst()

            Task { @MainActor in
                if !self.audioEngine.isRunning { try? self.audioEngine.start() }
                if !self.audioPlayer.isPlaying { self.audioPlayer.play() }

                self.audioPlayer.scheduleBuffer(bufferToPlay) {
                    self.playNextBuffer()
                }
            }
        }
    }
    
    private func setupOutputMeteringSafely() {
        let mixer = audioEngine.mainMixerNode
        let outputFormat = mixer.outputFormat(forBus: 0)
        
        // Remove existing tap if any
        do {
            mixer.removeTap(onBus: 0)
        } catch {
            // No tap to remove
        }
        
        // Install new tap
        mixer.installTap(onBus: 0, bufferSize: 1024, format: outputFormat) { [weak self] buffer, _ in
            self?.updateMeters(from: buffer)
        }
    }
    
    
    func setMic(active: Bool) {
        guard isMicrophoneAvailable else { return }
        
        // Update the mute state
        isMicMuted = !active
        
        // Control the input volume based on mute state
        if active {
            audioEngine.inputNode.volume = 1.0
            print("[Debug] Microphone unmuted")
        } else {
            audioEngine.inputNode.volume = 0
            print("[Debug] Microphone muted")
        }
    }

    
    private func updateMeters(from pcmBuffer: AVAudioPCMBuffer) {
        guard let floatData = pcmBuffer.floatChannelData?.pointee else { return }
        
        let frameLength = Int(pcmBuffer.frameLength)
        var rms: Float = 0
        vDSP_rmsqv(floatData, 1, &rms, vDSP_Length(frameLength))
        
        let bucketCount = latestSpectrum.count
        let stride = max(1, frameLength / bucketCount)
        var spectrum = [Float](repeating: 0, count: bucketCount)
        
        for i in 0..<bucketCount {
            spectrum[i] = fabsf(floatData[i * stride])
        }
        
        DispatchQueue.main.async {
            self.currentLevel = rms
            self.latestSpectrum = spectrum
        }
    }
    

    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        // Use AVAudioApplication for visionOS compatibility
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }
}

// MARK: - Helper Extensions

extension AVAudioPCMBuffer {
    func toData() -> Data? {
        guard let int16ChannelData = self.int16ChannelData else { return nil }
        let bytesPerFrame = Int(self.format.streamDescription.pointee.mBytesPerFrame)
        let frameLength = Int(self.frameLength)
        let totalBytes = frameLength * bytesPerFrame
        return Data(bytes: int16ChannelData[0], count: totalBytes)
    }
}

extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCapacity = UInt32(count) / format.streamDescription.pointee.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        
        buffer.frameLength = frameCapacity
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        
        withUnsafeBytes { bufferPointer in
            audioBuffer.mData?.copyMemory(from: bufferPointer.baseAddress!, byteCount: count)
        }
        
        return buffer
    }
}
