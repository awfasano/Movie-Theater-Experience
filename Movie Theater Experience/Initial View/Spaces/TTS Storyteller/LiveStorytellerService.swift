//
//  LiveStorytellerService.swift - Enhanced Debugging Version
//  Movie Theater Experience
//
//  Updated to fix audio static and improve playback stability.
//

import Foundation
@preconcurrency import AVFoundation
import Accelerate
import Combine

@MainActor
final class LiveStorytellerService: ObservableObject {

    enum Status: Equatable {
        case idle, connecting, connected, permissionDenied, error(String)
    }
    
    private var canStreamAudio = false   // <— NEW
    @Published private(set) var status: Status = .idle
    @Published private(set) var isMicrophoneAvailable: Bool = false
    let transcriptPublisher = PassthroughSubject<String, Never>()

    // MARK: - WebSocket + Audio Engine
    private var webSocketTask: URLSessionWebSocketTask?
    private var voice: String = "Zephyr"
    private var instruction: String = "You are a helpful assistant."

    private var micInputConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    
    private var audioBufferQueue = [AVAudioPCMBuffer]()
    private let pcmQueue = DispatchQueue(label: "com.storyteller.pcmQueue")
    private var isPlayingFromQueue = false
    
    // MARK: - Audio System Components
    private let audioSession  = AVAudioSession.sharedInstance()
    private let audioEngine   = AVAudioEngine()
    private let audioPlayer   = AVAudioPlayerNode()

    private let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                  sampleRate: 16_000,
                                                  channels: 1,
                                                  interleaved: true)!

    // MARK: - Audio Metering
    private var currentLevel: Float = 0
    private var latestSpectrum: [Float] = Array(repeating: 0, count: 128)

    func getCurrentLevel() -> Float { currentLevel }
    func getSpectrum() -> [Float] { latestSpectrum }
    
    // MARK: - Public Methods
    
    func configure(voice: String, instruction: String) {
        self.voice = voice
        self.instruction = instruction
    }

    func connectAndStart(urlString: String) {
        checkMicrophonePermission { [weak self] hasPermission in
            guard let self = self else { return }
            
            guard hasPermission else {
                print("[Live] Microphone permission was not granted. Aborting connection.")
                return
            }
            
            self.status = .connecting
            
            guard let url = URL(string: urlString) else {
                self.status = .error("Invalid WebSocket URL")
                return
            }
            
            self.disconnect()
            self.setupAudioEngine()
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            if let host = url.host {
                request.setValue("https://\(host)", forHTTPHeaderField: "Origin")
            }
            
            self.webSocketTask = URLSession.shared.webSocketTask(with: request)
            self.webSocketTask?.resume()
            
            self.listenForMessages()
            
            self.webSocketTask?.sendPing { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.status = .error("Connection failed: \(error.localizedDescription)")
                    self.disconnect()
                } else {
                    Task { @MainActor in self.sendConfig() }
                }
            }
        }
    }
    
    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch audioSession.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            status = .permissionDenied
            completion(false)
        case .undetermined:
            audioSession.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if !granted {
                        self.status = .permissionDenied
                    }
                    completion(granted)
                }
            }
        @unknown default:
            status = .permissionDenied
            completion(false)
        }
    }

    func disconnect(silent: Bool = false) {
        canStreamAudio = false
        if audioEngine.isRunning {
            // **FIX**: Ensure taps are removed from ALL nodes before stopping.
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.mainMixerNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        pcmQueue.sync {
            audioBufferQueue.removeAll()
            isPlayingFromQueue = false
        }
        
        audioPlayer.stop()
        try? audioSession.setActive(false)

        if !silent {
            status = .idle
        }
    }
    
    // MARK: - WebSocket Communication

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.processMessage(message)
                self.listenForMessages()
                // In LiveStorytellerService.swift -> listenForMessages()
            case .failure(let error):
                // Add this line to see the exact error in your Xcode console.
                print("[WebSocket] Receive failed with error: \(error)")
                
                if (error as NSError).code != NSURLErrorCancelled {
                    Task { @MainActor in
                        self.status = .error("Connection lost: \(error.localizedDescription)")
                        self.disconnect()
                    }
                }
            }
        }
    }

    private func processMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["status"] as? String == "ready" {
                    Task { @MainActor in
                        self.status = .connected
                        self.canStreamAudio = true       // <— UNGATE HERE
                    }
                } else if let transcript = json["transcript"] as? String {
                    transcriptPublisher.send(transcript)
                }
            }
        case .data(let data):
            handleIncomingPCM(data)
        default: break
        }
    }
    
    func sendConfig() {
        // If you got an error on last session, consider clearing the voice:
        // if case .error = status { self.voice = "" }

        struct StorytellerConfig: Codable { let voice: String?; let instruction: String? }
        let payload = StorytellerConfig(
            voice: voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : voice,
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : instruction
        )
        do {
            let data = try JSONEncoder().encode(payload)
            webSocketTask?.send(.string(String(data: data, encoding: .utf8)!)) { [weak self] error in
                if let error { Task { @MainActor in self?.status = .error("Failed to send config: \(error.localizedDescription)") } }
            }
        } catch {
            Task { @MainActor in self.status = .error("Failed to encode configuration") }
        }
    }

    
    func send(text: String) {
        guard status == .connected else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }
    
    // MARK: - Audio Engine & Processing
    
    private func setupAudioEngine() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setPreferredIOBufferDuration(0.02) // Balanced latency
            try audioSession.setActive(true)
        } catch {
            status = .error("Failed to configure audio session: \(error.localizedDescription)")
            return
        }
        
        audioEngine.attach(audioPlayer)
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: nil)
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            startMicrophone()
            startOutputMetering()
        } catch {
            status = .error("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    private func startMicrophone() {
        guard audioSession.recordPermission == .granted else {
            isMicrophoneAvailable = false
            return
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 else {
            print("[Warning] No valid microphone format.")
            isMicrophoneAvailable = false
            return
        }
        
        micInputConverter = AVAudioConverter(from: inputFormat, to: recordingFormat)
        guard micInputConverter != nil else {
            print("[Warning] Failed to create microphone converter.")
            isMicrophoneAvailable = false
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processMicrophoneBuffer(buffer)
        }
        isMicrophoneAvailable = true
    }

    private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        guard canStreamAudio else { return }  // <— NEW: don’t send pre‑config
        guard let converter = micInputConverter else { return }
        
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * recordingFormat.sampleRate / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: outputFrameCapacity) else { return }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .haveData, let data = outputBuffer.toData() {
            webSocketTask?.send(.data(data)) { _ in }
        }
    }
    
    private func handleIncomingPCM(_ data: Data) {
        guard let backendFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true),
              let pcmBuffer = data.toPCMBuffer(format: backendFormat) else {
            return
        }
        
        let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        
        if playbackConverter == nil {
            playbackConverter = AVAudioConverter(from: backendFormat, to: outputFormat)
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
                Task { @MainActor in
                    self.playNextBufferFromQueue()
                }
            }
        }
    }
    
    // **FIX**: Reverted to a more stable, standard playback scheduling method.
    private func playNextBufferFromQueue() {
        guard !isPlayingFromQueue else { return }
        
        pcmQueue.async {
            guard !self.audioBufferQueue.isEmpty else { return }
            let buffer = self.audioBufferQueue.removeFirst()
            
            Task { @MainActor in
                self.isPlayingFromQueue = true
                
                if !self.audioEngine.isRunning {
                    do { try self.audioEngine.start() } catch {
                        print("[Error] Could not restart audio engine: \(error)")
                        self.isPlayingFromQueue = false
                        return
                    }
                }
                
                if !self.audioPlayer.isPlaying {
                    self.audioPlayer.play()
                }
                
                self.audioPlayer.scheduleBuffer(buffer) {
                    Task { @MainActor in
                        self.isPlayingFromQueue = false
                        self.playNextBufferFromQueue()
                    }
                }
            }
        }
    }
    
    private func startOutputMetering() {
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
}

// MARK: - Helper Structs & Extensions

private struct StorytellerConfig: Codable {
    let voice: String
    let instruction: String
}

extension AVAudioPCMBuffer {
    func toData() -> Data? {
        guard let int16ChannelData = self.int16ChannelData else { return nil }
        let bytesPerFrame = Int(self.format.streamDescription.pointee.mBytesPerFrame)
        let frameLength = Int(self.frameLength)
        
        let totalBytes = frameLength * bytesPerFrame
        let data = Data(bytes: int16ChannelData[0], count: totalBytes)
        return data
    }
}

extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCapacity = UInt32(count) / format.streamDescription.pointee.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        
        buffer.frameLength = frameCapacity
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        
        withUnsafeBytes { (bufferPointer) in
            audioBuffer.mData?.copyMemory(from: bufferPointer.baseAddress!, byteCount: count)
        }
        
        return buffer
    }
}
