//
//  LiveStorytellerService.swift - Enhanced Debugging Version
//  Movie Theater Experience
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
    
    @Published private(set) var status: Status = .idle
    @Published private(set) var isMicrophoneAvailable: Bool = false
    let transcriptPublisher = PassthroughSubject<String, Never>()

    // MARK: - WebSocket + Audio Engine
    private var webSocketTask: URLSessionWebSocketTask?
    private var voice: String = "Zephyr"
    private var instruction: String = "You are a helpful assistant."
    private var lastEngineRestart = Date(timeIntervalSince1970: 0)
    private var needsPrime = true


    private var micInputConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    
    private var audioBufferQueue: [AVAudioPCMBuffer] = []
    private var isPlayingFromQueue = false
    private let pcmQueue = DispatchQueue(label: "pcmQueue")
    
    // MARK: - Audio System Components
    private let audioSession  = AVAudioSession.sharedInstance()
    private let audioEngine   = AVAudioEngine()
    private let audioPlayer   = AVAudioPlayerNode()

    // FIXED: Corrected recording format - backend expects 16kHz mono PCM
    private let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                  sampleRate: 16_000,
                                                  channels: 1,
                                                  interleaved: true)!

    // MARK: - Audio Metering (UI pulls these)
    private var currentLevel: Float = 0
    private var latestSpectrum: [Float] = Array(repeating: 0, count: 128)

    func getCurrentLevel() -> Float { currentLevel }
    func getSpectrum() -> [Float] { latestSpectrum }
    
    // MARK: - Public Methods
    
    func configure(voice: String, instruction: String) {
        self.voice = voice
        self.instruction = instruction
        print("[DEBUG] Configured with voice: \(voice)")
    }

    func connectAndStart(urlString: String) {
        checkMicrophonePermission { [weak self] hasPermission in
            guard let self = self, hasPermission else {
                return
            }
            
            print("[DEBUG] Attempting to connect to: \(urlString)")
            
            guard let url = URL(string: urlString) else {
                print("[DEBUG] Invalid URL: \(urlString)")
                self.status = .error("Invalid WebSocket URL")
                return
            }
            
            self.disconnect()
            self.status = .connecting
            print("[Live] Starting connection...")
            
            // Setup audio BEFORE WebSocket connection
            self.setupAudioEngine()
            
            // Small delay to ensure audio is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Create WebSocket with custom configuration for debugging
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                
                // Add headers if needed (some servers require Origin header)
                request.setValue("https://storyteller-457201302256.us-east5.run.app", forHTTPHeaderField: "Origin")
                
                self.webSocketTask = URLSession.shared.webSocketTask(with: request)
                self.webSocketTask?.resume()
                
                print("[DEBUG] WebSocket task created and resumed")
                
                // Start listening for messages
                self.listenForMessages()
                
                // Send a ping to verify connection is established, then send config
                self.webSocketTask?.sendPing { [weak self] error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("[DEBUG] Ping failed: \(error)")
                        self.status = .error("Connection failed: \(error.localizedDescription)")
                        self.disconnect()
                    } else {
                        print("[DEBUG] Ping successful - connection established")
                        // Now send the config
                        Task { @MainActor in
                            self.sendConfig()
                        }
                    }
                }
            }
        }
    }
    
    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
            
        case .granted:
            completion(true)
            
        case .denied:
            print("[Permission] Microphone access was denied.")
            status = .permissionDenied
            completion(false)
            
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("[Permission] Microphone access granted.")
                        completion(true)
                    } else {
                        print("[Permission] Microphone access was denied.")
                        self.status = .permissionDenied
                        completion(false)
                    }
                }
            }
            
        @unknown default:
            status = .permissionDenied
            completion(false)
        }
    }
    

    func disconnect(silent: Bool = false) {
        print("[DEBUG] Disconnect called")

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.mainMixerNode.removeTap(onBus: 0)   // <-- add this
            audioEngine.stop()
            audioPlayer.stop()
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        pcmQueue.sync {
            audioBufferQueue.removeAll()
            isPlayingFromQueue = false
        }

        try? audioSession.setActive(false)

        if !silent && status != .idle {          // <- only publish change if not silent
            status = .idle
        }
    }

    
    // MARK: - WebSocket Communication

    private func listenForMessages() {
        webSocketTask?.receive { result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                switch result {
                case .success(let message):
                    print("[DEBUG] Received message")
                    self.processMessage(message)
                    self.listenForMessages()

                case .failure(let error):
                    if (error as NSError).code != NSURLErrorCancelled {
                        print("[WS] Receive error: \(error.localizedDescription)")
                        print("[DEBUG] Error domain: \((error as NSError).domain)")
                        print("[DEBUG] Error code: \((error as NSError).code)")
                        self.status = .error("Connection failed: \(error.localizedDescription)")
                        self.disconnect()
                    }
                }
            }
        }
    }

    private func processMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            print("[DEBUG] Received string message: \(text)")
            
            // Handle JSON status messages from backend
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                if let status = json["status"] as? String {
                    print("[DEBUG] Received status: \(status)")
                    if status == "ready" {
                        print("[Live] Backend ready for audio streaming")
                        self.status = .connected
                    }
                } else if let transcript = json["transcript"] as? String {
                    self.transcriptPublisher.send(transcript)
                }
            } else {
                // Regular transcript text
                self.transcriptPublisher.send(text)
            }
            
        case .data(let data):
            print("[DEBUG] Received audio data: \(data.count) bytes")
            self.handleIncomingPCM(data)
            
        @unknown default:
            print("[DEBUG] Received unknown message type")
            break
        }
    }
    
    private func sendConfig() {
        let config = StorytellerConfig(voice: self.voice, instruction: self.instruction)
        
        do {
            let jsonData = try JSONEncoder().encode(config)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            print("[DEBUG] Sending config: \(jsonString)")
            
            webSocketTask?.send(.string(jsonString)) { error in
                if let error {
                    print("[ERROR] Failed to send configuration: \(error)")
                    Task { @MainActor in
                        self.status = .error("Failed to send config: \(error.localizedDescription)")
                        self.disconnect()
                    }
                } else {
                    print("[DEBUG] Configuration sent successfully")
                }
            }
        } catch {
            print("[ERROR] Failed to encode config: \(error)")
            status = .error("Failed to encode configuration")
        }
    }
    
    func send(text: String) {
        guard status == .connected else {
            print("[WS] Cannot send text - not connected (status: \(status))")
            return
        }
        
        print("[DEBUG] Sending text: \(text)")
        
        webSocketTask?.send(.string(text)) { err in
            if let err {
                print("[WS] text send error:", err)
            } else {
                print("[DEBUG] Text sent successfully")
            }
        }
    }
    
    // MARK: - Audio Engine & Processing
    // In LiveStorytellerService.swift

    private func setupAudioEngine() {

        // 1️⃣ Wire up the graph (cheap, can stay here)
        audioEngine.attach(audioPlayer)
        audioEngine.connect(audioPlayer,
                            to: audioEngine.mainMixerNode,
                            format: nil)
        audioEngine.prepare()

        // 2️⃣ Start the engine and configure the session OFF the main thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // --- MOVE AUDIO SESSION SETUP HERE ---
            do {
                /* Audio-session configuration (now on a background thread) */
                try self.audioSession.setCategory(.playAndRecord,
                                             mode: .voiceChat,
                                             options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
                try self.audioSession.setPreferredIOBufferDuration(0.04) // 40 ms
                try self.audioSession.setActive(true)
                print("[DEBUG] Audio session configured successfully (async)")
            } catch {
                print("[WARNING] Audio session error:", error)
                // Handle error appropriately...
            }
            // --- END OF MOVED CODE ---

            do {
                try self.audioEngine.start() // ⏳ heavy call
                print("[DEBUG] Audio engine started (async)")

                await MainActor.run {
                    self.audioPlayer.play()
                    self.startMicrophone()
                    self.startOutputMetering()
                    self.installEngineObservers()
                }
            } catch {
                print("[ERROR] Audio engine start failed:", error)
                // Handle fallback...
            }
        }
    }


    private func handleIncomingPCM(_ data: Data) {
        let backendSampleRate: Double = 24_000      // matches server

        guard let srcFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: backendSampleRate,
                                            channels: 1,
                                            interleaved: true),
              let srcBuf = data.toPCMBuffer(format: srcFormat)
        else {
            print("[Audio] Failed to create PCM buffer from incoming data")
            return
        }

        updateMeters(from: srcBuf)

        let dstFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)

        if playbackConverter == nil {
            playbackConverter = AVAudioConverter(from: srcFormat, to: dstFormat)
            print("[DEBUG] Created playback converter \(srcFormat.sampleRate) → \(dstFormat.sampleRate)")
        }
        guard let converter = playbackConverter else { return }

        let dstCap = AVAudioFrameCount(Double(srcBuf.frameLength) *
                                       (dstFormat.sampleRate / srcFormat.sampleRate))
        guard let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFormat,
                                            frameCapacity: dstCap) else { return }

        var error: NSError?
        let status = converter.convert(to: dstBuf, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return srcBuf
        }
        if status != .haveData { return }

        // ---------- enqueue & kick the scheduler ----------
        pcmQueue.async {
            self.audioBufferQueue.append(dstBuf)
            if !self.isPlayingFromQueue {
                self.isPlayingFromQueue = true
                DispatchQueue.main.async { self.playNextBufferFromQueue() }
            }
        }
    }
    
    // LiveStorytellerService.swift (anywhere inside the class)

    private func startOutputMetering() {
        let mix = audioEngine.mainMixerNode
        mix.removeTap(onBus: 0)                         // <-- safe even if no tap

        let fmt = mix.outputFormat(forBus: 0)
        let bufferSize: AVAudioFrameCount = 1_024

        mix.installTap(onBus: 0,
                       bufferSize: bufferSize,
                       format: fmt) { [weak self] buf, _ in
            self?.updateMeters(from: buf)
        }
    }

    

    
    @MainActor
    private func attemptEngineRestart() {
        guard !audioEngine.isRunning,
              Date().timeIntervalSince(lastEngineRestart) > 1 else { return }

        do   { try audioEngine.start(); lastEngineRestart = Date() }
        catch { print("[Audio] Engine restart failed: \(error)") }
    }
    
    
    private func installEngineObservers() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            self?.attemptEngineRestart()
        }
    }

    @MainActor
    private func playNextBufferFromQueue() {

        attemptEngineRestart()

        if !audioPlayer.isPlaying {
            audioPlayer.play()
        }

        pcmQueue.async { [weak self] in
            guard let self = self else { return }

            // ----- dequeue first buffer -----
            if self.audioBufferQueue.isEmpty {
                self.isPlayingFromQueue = false
                self.needsPrime = true
                return
            }
            let firstBuf = self.audioBufferQueue.removeFirst()

            let buffersToSchedule = self.needsPrime ? 2 : 1
            self.needsPrime = false

            for i in 0..<buffersToSchedule {
                let buf = (i == 0) ? firstBuf :
                          (self.audioBufferQueue.isEmpty ? firstBuf
                                                         : self.audioBufferQueue.removeFirst())

                self.audioPlayer.scheduleBuffer(buf) { [weak self] in
                    Task { @MainActor in self?.playNextBufferFromQueue() }
                }
            }
        }
    }

    
    // FIXED: Improved microphone processing with better debugging
    private func startMicrophone() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            print("[WARNING] No valid microphone format - continuing without microphone")
            print("[WARNING] Sample rate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")
            isMicrophoneAvailable = false
            // Don't set error status - we can still receive audio
            return
        }
        
        print("[Audio] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        print("[Audio] Target format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount) channels")
        
        micInputConverter = AVAudioConverter(from: inputFormat, to: recordingFormat)
        guard micInputConverter != nil else {
            print("[WARNING] Failed to create microphone converter - continuing without microphone")
            isMicrophoneAvailable = false
            return
        }
        
        // Use smaller buffer size for lower latency
        let bufferSize: AVAudioFrameCount = 512
        
        do {
            inputNode.removeTap(onBus: 0)   // right before you install the new tap
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self,
                      let task = self.webSocketTask,
                      let converter = self.micInputConverter,
                      self.status == .connected
                else { return }
                
                let frameCap = AVAudioFrameCount(self.recordingFormat.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate)
                guard let convBuf = AVAudioPCMBuffer(pcmFormat: self.recordingFormat, frameCapacity: frameCap) else {
                    print("[Audio] Failed to create conversion buffer")
                    return
                }
                
                var error: NSError?
                let convStatus = converter.convert(to: convBuf, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                
                if let error {
                    print("[Audio] Mic conversion error: \(error)")
                    return
                }
                
                if convStatus != .haveData {
                    print("[Audio] Mic conversion failed with status: \(convStatus)")
                    return
                }
                
                if let data = convBuf.toData() {
                    // Only log occasionally to avoid spam
                    var logCounter = 0
                    logCounter += 1
                    if logCounter % 100 == 0 {
                        print("[Audio] Sending audio data (sample \(logCounter))")
                    }
                    
                    task.send(.data(data)) { err in
                        if let err {
                            print("[WS] Mic data send error:", err.localizedDescription)
                        }
                    }
                }
            }
            
            print("[DEBUG] Microphone tap installed successfully")
            isMicrophoneAvailable = true
        } catch {
            print("[WARNING] Failed to install microphone tap: \(error) - continuing without microphone")
            isMicrophoneAvailable = false
        }
    }

    func setMic(active: Bool) {
        // Check if we actually have a microphone before trying to set volume
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        if inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 {
            print("[DEBUG] Setting mic active: \(active)")
            audioEngine.inputNode.volume = active ? 1 : 0
        } else {
            print("[DEBUG] No microphone available - ignoring mic activation request")
        }
    }
    
    // FIXED: Improved metering with bounds checking
    // MARK: - Improved metering that supports Float32 *and* Int16
    private func updateMeters(from pcmBuffer: AVAudioPCMBuffer) {

        let frames = Int(pcmBuffer.frameLength)
        guard frames > 0 else { return }

        let bucketCount = latestSpectrum.count
        let stride      = max(1, frames / bucketCount)

        var snap  = [Float](repeating: 0, count: bucketCount)
        var sqSum: Float = 0

        switch pcmBuffer.format.commonFormat {

        case .pcmFormatFloat32:
            guard let floatPtr = pcmBuffer.floatChannelData?.pointee else { return }

            for i in 0..<bucketCount {
                let sample = floatPtr[i * stride]          // already −1…+1
                snap[i]  = fabsf(sample)
                sqSum   += sample * sample
            }

        case .pcmFormatInt16:
            guard let intPtr = pcmBuffer.int16ChannelData?.pointee else { return }
            let scale: Float = 1.0 / Float(Int16.max)      // convert to −1…+1

            for i in 0..<bucketCount {
                let sample = Float(intPtr[i * stride]) * scale
                snap[i]  = fabsf(sample)
                sqSum   += sample * sample
            }

        default:                                           // unsupported format
            return
        }

        let rms = sqrtf(sqSum / Float(bucketCount))

        DispatchQueue.main.async {                         // UI thread
            self.latestSpectrum = snap
            self.currentLevel   = min(rms * 1.5, 1.0)
        }
    }
}

// MARK: - Configuration struct
private struct StorytellerConfig: Codable {
    let voice: String
    let instruction: String
}

// MARK: - Buffer/Data helpers (FIXED)
extension AVAudioPCMBuffer {
    func toData() -> Data? {
        guard let chData = int16ChannelData else { return nil }
        let frameLength = Int(self.frameLength)
        let bytesPerFrame = Int(self.format.streamDescription.pointee.mBytesPerFrame)
        let totalBytes = frameLength * bytesPerFrame
        
        return Data(bytes: chData[0], count: totalBytes)
    }
}

extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let frameLength = UInt32(self.count) / UInt32(bytesPerFrame)
        
        guard frameLength > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        
        buf.frameLength = frameLength
        
        guard let dst = buf.int16ChannelData else { return nil }
        
        self.withUnsafeBytes { srcPtr in
            guard let src = srcPtr.baseAddress else { return }
            dst[0].assign(from: src.assumingMemoryBound(to: Int16.self), count: Int(frameLength))
        }
        return buf
    }
}
