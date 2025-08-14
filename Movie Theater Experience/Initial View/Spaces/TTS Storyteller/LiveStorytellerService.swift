//
//  LiveStorytellerService.swift
//  Movie Theater Experience
//
//  Updated to work with the deployed Gemini Live API web service
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
    
    struct TranscriptEntry: Identifiable {
        let id = UUID()
        let role: String  // "user" or "model"
        let text: String
        let isFinal: Bool
    }
    
    // WebSocket connection
    private var webSocketTask: URLSessionWebSocketTask?
    private var voice: String = "Puck"
    private var instruction: String = "You are a helpful storyteller."
    
    // Audio components
    private let audioSession = AVAudioSession.sharedInstance()
    private let audioEngine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()
    
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
        checkMicrophonePermission { [weak self] hasPermission in
            guard let self = self else { return }
            
            if !hasPermission {
                self.status = .permissionDenied
                self.isMicrophoneAvailable = false
                // Continue anyway - user can use text
            }
            
            self.status = .connecting
            
            // Use the correct WebSocket endpoint
            let wsURLString = urlString.replacingOccurrences(of: "https://", with: "wss://")
                .replacingOccurrences(of: "http://", with: "ws://")
            let fullURLString = wsURLString.hasSuffix("/live-chat") ? wsURLString : "\(wsURLString)/live-chat"
            
            guard let url = URL(string: fullURLString) else {
                self.status = .error("Invalid WebSocket URL")
                return
            }
            
            self.disconnect(silent: true)
            self.setupAudioEngine()
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            
            self.webSocketTask = URLSession.shared.webSocketTask(with: request)
            self.webSocketTask?.resume()
            
            // Send configuration immediately after connection
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                self.sendConfiguration()
            }
            
            self.listenForMessages()
            self.startPingTimer()
        }
    }
    
    private func sendConfiguration() {
        let config: [String: Any] = [
            "system_instruction": instruction,
            "voice_name": voice,
            "max_context_turns": 8
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            status = .error("Failed to create configuration")
            return
        }
        
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.status = .error("Failed to send config: \(error.localizedDescription)")
                }
            } else {
                Task { @MainActor in
                    self?.status = .connected
                }
            }
        }
    }
    
    func disconnect(silent: Bool = false) {
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.mainMixerNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        
        // Close WebSocket
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        // Clear audio buffers
        pcmQueue.sync {
            audioBufferQueue.removeAll()
            isPlayingFromQueue = false
        }
        
        audioPlayer.stop()
        hasStartedPlayback = false // <-- ADD THIS LINE

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
                    }
                }
            }
        }
    }
    
    private func processMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            // Handle JSON messages (transcripts)
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                if let type = json["type"] as? String, type == "transcript" {
                    if let role = json["role"] as? String,
                       let transcriptText = json["text"] as? String,
                       let isFinal = json["is_final"] as? Bool {
                        
                        Task { @MainActor in
                            // Update or add transcript
                            if !isFinal {
                                // Update existing partial transcript
                                if let lastIndex = self.transcripts.lastIndex(where: { $0.role == role && !$0.isFinal }) {
                                    self.transcripts[lastIndex] = TranscriptEntry(role: role, text: transcriptText, isFinal: false)
                                } else {
                                    self.transcripts.append(TranscriptEntry(role: role, text: transcriptText, isFinal: false))
                                }
                            } else {
                                // Replace partial with final or add new final
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
            // Handle audio data (PCM16 @ 24kHz from server)
            print("✅ [Audio Debug] Received \(data.count) bytes of audio data.") // <-- ADD THIS
            handleIncomingAudio(data)
            
        @unknown default:
            break
        }
    }
    
    func send(text: String) {
        guard status == .connected else { return }
        
        let message: [String: Any] = [
            "type": "text",
            "data": text
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        webSocketTask?.send(.string(jsonString)) { _ in }
    }
    
    private func startPingTimer() {
        Task {
            while webSocketTask != nil {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                webSocketTask?.sendPing { _ in }
            }
        }
    }
    
    // MARK: - Audio Setup
    
    private func setupAudioEngine() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("[Audio] Failed to configure session: \(error)")
            return
        }
        
        audioEngine.attach(audioPlayer)
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: nil)
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            setupMicrophone()
            setupOutputMetering()
        } catch {
            print("[Audio] Engine failed to start: \(error)")
        }
    }
    
    private func setupMicrophone() {
        guard audioSession.recordPermission == .granted else {
            isMicrophoneAvailable = false
            return
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 else {
            isMicrophoneAvailable = false
            return
        }
        
        micInputConverter = AVAudioConverter(from: inputFormat, to: recordingFormat)
        guard micInputConverter != nil else {
            isMicrophoneAvailable = false
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processMicrophoneBuffer(buffer)
        }
        
        isMicrophoneAvailable = true
    }
    
    private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
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
            // Send raw PCM16 audio to server
            webSocketTask?.send(.data(data)) { _ in }
        }
    }
    
    // In LiveStorytellerService.swift

    // In LiveStorytellerService.swift

    private func handleIncomingAudio(_ data: Data) {
        // This function's audio conversion logic remains the same.
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

        // The queuing logic is what's new.
        if error == nil {
            pcmQueue.async {
                self.audioBufferQueue.append(outputBuffer)

                // If playback hasn't started and we've collected enough chunks,
                // kick off the playback loop on the main thread.
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
            // If the queue runs out of data, stop and reset the flag.
            // Playback will restart automatically once the buffer fills up again.
            guard !self.audioBufferQueue.isEmpty else {
                Task { @MainActor in self.hasStartedPlayback = false }
                return
            }

            let bufferToPlay = self.audioBufferQueue.removeFirst()

            Task { @MainActor in
                // Ensure the audio engine and player node are running.
                if !self.audioEngine.isRunning { try? self.audioEngine.start() }
                if !self.audioPlayer.isPlaying { self.audioPlayer.play() }

                // Schedule the buffer. The completion handler immediately calls this
                // function again, creating a self-sustaining and seamless playback loop.
                self.audioPlayer.scheduleBuffer(bufferToPlay) {
                    self.playNextBuffer()
                }
            }
        }
    }
    
    private func setupOutputMetering() {
        let mixer = audioEngine.mainMixerNode
        let outputFormat = mixer.outputFormat(forBus: 0)
        
        mixer.installTap(onBus: 0, bufferSize: 1024, format: outputFormat) { [weak self] buffer, _ in
            self?.updateMeters(from: buffer)
        }
    }
    
    func setMic(active: Bool) {
        guard isMicrophoneAvailable else { return }
        audioEngine.inputNode.volume = active ? 1 : 0
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
        switch audioSession.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            audioSession.requestRecordPermission { granted in
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
