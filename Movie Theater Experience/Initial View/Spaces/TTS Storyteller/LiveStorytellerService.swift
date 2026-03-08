//
//  LiveStorytellerService.swift
//  Movie Theater Experience
//
//  Revised for stable transcripts, correct message handling, improved AVAudioSession management, and compilation fix.
//

import Foundation
import AVFoundation
import Accelerate
import Combine

@MainActor
final class LiveStorytellerService: ObservableObject {

    // MARK: - Public State

    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case permissionDenied
        case error(String)
    }

    // TranscriptEntry ensures the ID remains stable during updates.
    struct TranscriptEntry: Identifiable {
        let id: UUID
        let role: String      // "user" or "model"
        let text: String
        let isFinal: Bool
        
        // Initialize with an optional ID. If nil (default), create a new one.
        init(id: UUID? = nil, role: String, text: String, isFinal: Bool) {
            self.id = id ?? UUID()
            self.role = role
            self.text = text
            self.isFinal = isFinal
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var isMicrophoneAvailable = false
    @Published private(set) var isMicMuted = true
    @Published private(set) var isSendingAudio = false
    @Published private(set) var isSendingText = false
    @Published private(set) var isWaitingForResponse = false
    @Published private(set) var transcripts: [TranscriptEntry] = []
    
    // Dedicated queue for audio conversion tasks (High priority)
    private let playbackQueue = DispatchQueue(label: "com.storyteller.playback.convert", qos: .userInitiated)
    private var isShuttingDown = false

    // MARK: - Reconnection Backoff

    private var reconnectAttempts: Int = 0
    private static let maxBackoffSeconds: Double = 30.0

    /// Returns the backoff delay in seconds using exponential backoff: 1, 2, 4, 8, ... capped at 30s.
    private var reconnectBackoffDelay: Double {
        min(pow(2.0, Double(reconnectAttempts)), Self.maxBackoffSeconds)
    }

    // MARK: - Config

    private var voice: String = "Puck"
    private var instruction: String = "You are a helpful storyteller."

    func configure(voice: String, instruction: String) {
        self.voice = voice
        self.instruction = instruction
    }

    // MARK: - WebSocket

    private var webSocketTask: URLSessionWebSocketTask?

    // REVISED: Restructured using 'if' statements instead of 'guard'.
    func connectAndStart(urlString: String) {
        // Check current status to prevent re-entry or determine if a reset is needed.
        
        if status == .connecting || status == .connected {
            // Already connecting or connected, exit early.
            return
        }
        
        if status == .permissionDenied && webSocketTask != nil {
            // Already connected (text only), exit early.
            return
        }
        
        // If we are not idle or in a simple error state, we should reset before attempting to connect.
        if status != .idle && status != .error("Connection error") {
             disconnect(silent: true)
        }
        
        // Apply exponential backoff on retries
        if reconnectAttempts > 0 {
            let delay = reconnectBackoffDelay
            status = .connecting
            Task {
                try? await Task.sleep(for: .seconds(delay))
                await self.performConnect(urlString: urlString)
            }
            return
        }

        status = .connecting
        performConnect(urlString: urlString)
    }

    private func performConnect(urlString: String) {
        reconnectAttempts += 1

        checkMicrophonePermission { [weak self] granted in
            guard let self else { return }
            if !granted {
                // Set permission denied status but still allow connection for text chat
                if self.status == .connecting {
                     self.status = .permissionDenied
                }
            }
            Task {
                do {
                    // setupAudioEngine configures the AVAudioSession for .playAndRecord
                    try await self.setupAudioEngine()
                    self.openWebSocket(urlString: urlString)
                } catch {
                    print("[Live] Audio setup failed: \(error)")
                    // If audio setup fails, update status if it hasn't already changed (e.g. to permissionDenied)
                    if self.status == .connecting {
                         self.status = .error("Audio setup failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func send(text: String) {
        // Allow sending text even if mic permission was denied
        guard (status == .connected || status == .permissionDenied), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSendingText = true
        
        // We rely on the server to echo the transcript back to us. Do not append manually.
        
        let message: [String: Any] = ["type": "text", "data": text]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let s = String(data: data, encoding: .utf8) else {
            isSendingText = false
            return
        }
        webSocketTask?.send(.string(s)) { [weak self] err in
            Task { @MainActor in
                self?.isSendingText = false
                // Assume we are waiting for a response if the send succeeded
                if err == nil {
                    self?.isWaitingForResponse = true
                } else {
                    print("[Live] Text send failed: \(String(describing: err))")
                }
            }
        }
    }

    func setMic(active: Bool) {
        guard isMicrophoneAvailable else { return }
        isMicMuted = !active
        // Don’t remove taps, just lower/raise input gain for click-free UX.
        audioEngine.inputNode.volume = active ? 1.0 : 0.0
    }

    func disconnect(silent: Bool = false) {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        cleanupAudioEngine()

        if !silent {
            transcripts.removeAll()
            reconnectAttempts = 0
            status = .idle
        }
        isSendingAudio = false
        isSendingText = false
        isWaitingForResponse = false
    }

    // MARK: - WebSocket internals (No changes needed below this point)

    private func openWebSocket(urlString: String) {
        let wsURLString = urlString.replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let fullURLString = wsURLString.hasSuffix("/live-chat") ? wsURLString : "\(wsURLString)/live-chat"

        guard let url = URL(string: fullURLString) else {
            if status == .connecting {
                 status = .error("Invalid WebSocket URL")
            }
            return
        }

        let request = URLRequest(url: url, timeoutInterval: 30)
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        listenForMessages()
        Task { try? await Task.sleep(nanoseconds: 150_000_000); await sendConfiguration() }
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.processMessage(message)
                self.listenForMessages()
            case .failure(let error):
                Task { @MainActor in
                    if (error as NSError).code != NSURLErrorCancelled {
                        // Only update status if we haven't already encountered an error or permission issue
                        if self.status != .permissionDenied {
                             self.status = .error("Connection error: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    private func sendConfiguration() async {
        // Tell the server what we want back (24kHz) and what we’ll send up (16kHz).
        let config: [String: Any] = [
            "system_instruction": instruction,
            "voice_name": voice,
            "max_context_turns": 8,

            "return_audio": true,
            "audio_format": "pcm_s16le",
            "audio_sample_rate_hz": 24000,
            "return_transcripts": true,

            "input_audio_format": "pcm_s16le",
            "input_audio_sample_rate_hz": 16000
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: jsonData, encoding: .utf8) else {
            if status == .connecting {
                status = .error("Failed to encode configuration")
            }
            return
        }

        webSocketTask?.send(.string(json)) { [weak self] err in
            Task { @MainActor in
                guard let self = self else { return }
                if let err = err {
                    if self.status == .connecting {
                        self.status = .error("Config send failed: \(err.localizedDescription)")
                    }
                } else {
                    print("[Live] config sent.")
                    if self.status == .connecting {
                        self.reconnectAttempts = 0
                        self.status = .connected
                    }
                }
            }
        }
    }
    
    private func b64ToData(_ s: String) -> Data? {
        // Be resilient to URL-safe or padded/unstyled base64
        let fixed = s.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        // Try standard first
        if let d = Data(base64Encoded: fixed, options: [.ignoreUnknownCharacters]) { return d }
        // Try URL-safe
        let urlSafe = fixed.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        var padded = urlSafe
        let pad = 4 - (padded.count % 4)
        if pad > 0 && pad < 4 { padded.append(String(repeating: "=", count: pad)) }
        return Data(base64Encoded: padded, options: [.ignoreUnknownCharacters])
    }

    // Ensure default for 'is_final' is consistently false if missing.
    private func processMessage(_ message: URLSessionWebSocketTask.Message) {
        // Stop waiting when we receive any message (audio or transcript)
        Task { @MainActor in isWaitingForResponse = false }

        switch message {
        case .data(let raw):
            // print("[Live<-WS] data \(raw.count) bytes")
            handleIncomingAudio(raw)

        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return
            }

            // 0) Setup ack
            if json["setupComplete"] != nil {
                print("[Live] setupComplete")
                return
            }

            // 1) Audio payloads: handle several common shapes
            if let audioB64 = json["audio_chunk"] as? String ?? json["audio_b64"] as? String {
                if let d = b64ToData(audioB64) { handleIncomingAudio(d) }
                return
            }
            if let audio = json["audio"] as? [String: Any] {
                // { "audio": { "data": "<b64>", "encoding":"pcm_s16le", "sample_rate_hz": 24000 } }
                if let s = audio["data"] as? String, let d = b64ToData(s) { handleIncomingAudio(d) }
                return
            }

            // 2) Transcript variants
            // Default for 'is_final' is FALSE (partial) if the key is missing.
            
            if let t = json["transcript"] as? [String: Any] {
                appendTranscript(role: t["role"] as? String,
                                 text: t["text"] as? String,
                                 final: t["is_final"] as? Bool ?? false)
                return
            }
            if let role = json["role"] as? String, let content = json["text"] as? String {
                // e.g. {"role":"assistant","text":"Hello...", "is_final":true}
                appendTranscript(role: role, text: content, final: json["is_final"] as? Bool ?? false)
                return
            }
            if let partial = json["partial"] as? String {
                appendTranscript(role: "model", text: partial, final: false)
                return
            }
            if let final = json["final"] as? String {
                appendTranscript(role: "model", text: final, final: true)
                return
            }
            if let turn = json["turn"] as? [String: Any] {
                // e.g. {"turn":{"role":"assistant","text":"..."}}
                // A 'turn' implies a final message.
                appendTranscript(role: (turn["role"] as? String) ?? "model",
                                 text: turn["text"] as? String,
                                 final: true)
                return
            }

            // 3) Unknown event → ignore
        @unknown default:
            break
        }
    }

    // Updated to preserve the ID when coalescing partial transcripts.
    @MainActor
    private func appendTranscript(role: String?, text: String?, final: Bool) {
        guard let role = role, let text = text, !text.isEmpty else { return }
        
        // Find the index of the last message for this role that is NOT final.
        let idx = transcripts.lastIndex(where: { $0.role == role && !$0.isFinal })

        if !final {
            // Handle partial updates
            if let idx = idx {
                // If an existing partial entry is found, update it.
                // CRITICAL: Reuse the existing ID to ensure SwiftUI updates in place.
                let existingID = transcripts[idx].id
                transcripts[idx] = TranscriptEntry(id: existingID, role: role, text: text, isFinal: false)
            } else {
                // Otherwise, create a new partial entry (new ID generated automatically).
                transcripts.append(TranscriptEntry(role: role, text: text, isFinal: false))
            }
        } else {
            // Handle final updates
            if let idx = idx {
                // If an existing partial entry is found, finalize it.
                // CRITICAL: Reuse the existing ID.
                let existingID = transcripts[idx].id
                transcripts[idx] = TranscriptEntry(id: existingID, role: role, text: text, isFinal: true)
            } else {
                // Otherwise, create a new final entry (e.g., if no partial was received).
                transcripts.append(TranscriptEntry(role: role, text: text, isFinal: true))
            }
        }
    }

    // MARK: - Audio: Engine + Mic + Playback

    private let audioSession = AVAudioSession.sharedInstance()
    private let audioEngine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()

    // Outgoing mic → server: 16 kHz mono PCM16
    private let captureFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                              sampleRate: 16_000,
                                              channels: 1,
                                              interleaved: true)!

    // Server inbound PCM16 24 kHz mono (We rely on this format)
    private let expectedInboundFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                      sampleRate: 24_000,
                                                      channels: 1,
                                                      interleaved: true)!

    // Converters
    private var micInputConverter: AVAudioConverter?
    // Access synchronized via playbackQueue
    nonisolated(unsafe) private var playbackConverter: AVAudioConverter?
    nonisolated(unsafe) private var lastInboundPlaybackFormat: AVAudioFormat?


    // Buffering (Simplified)
    private var isPlayerAttached = false

    // Metering (simple)
    private var latestSpectrum = [Float](repeating: 0, count: 128)
    private var currentLevel: Float = 0
    func getSpectrum() -> [Float] { latestSpectrum }
    func getCurrentLevel() -> Float { currentLevel }

    // MARK: Setup
    
    // Helper to define the standard internal processing format
    private func getProcessingFormat(sampleRate: Double) -> AVAudioFormat? {
        // Standard format for AVAudioEngine: Float32, Stereo (for compatibility), non-interleaved
        return AVAudioFormat(commonFormat: .pcmFormatFloat32,
                             sampleRate: sampleRate,
                             channels: 2,
                             interleaved: false)
    }
    
    private func dumpAudioRoute(_ tag: String) {
        let s = AVAudioSession.sharedInstance()
        let outs = s.currentRoute.outputs.map { "\($0.portType.rawValue)::\($0.portName)" }.joined(separator: ", ")
        let ins  = s.currentRoute.inputs.map  { "\($0.portType.rawValue)::\($0.portName)" }.joined(separator: ", ")
        print("\(tag) ROUTE OUT=[\(outs)]  IN=[\(ins)]  SR=\(s.sampleRate)  IOBuffer=\(s.ioBufferDuration)")
    }

    // This function configures the session for PlayAndRecord
    private func setupAudioEngine() async throws {
        // Duplex session configuration
        try audioSession.setCategory(.playAndRecord,
                                     mode: .voiceChat,
                                     options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try audioSession.setPreferredIOBufferDuration(0.01)
        // Activate the session for this configuration
        try audioSession.setActive(true)

        // Player→mixer connection (standardized format)
        attachAndConnectPlayerIfNeeded()

        print("[Live] Effective session category=\(audioSession.category.rawValue), mode=\(audioSession.mode.rawValue)")
        
        // Prepare mic converter
        let input = audioEngine.inputNode
        // Use inputFormat to get the hardware format
        let inFormat = input.inputFormat(forBus: 0)
        
        if inFormat.sampleRate > 0 {
            micInputConverter = AVAudioConverter(from: inFormat, to: captureFormat)

            // Tap mic
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buf, _ in
                self?.processMicBuffer(buf)
            }
            isMicrophoneAvailable = true
        } else {
            print("[Live] Warning: Input node sample rate is 0. Microphone unavailable.")
            isMicrophoneAvailable = false
        }

        // Output metering (cheap)
        let mixer = audioEngine.mainMixerNode
        let outFormat = mixer.outputFormat(forBus: 0)
        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 1024, format: outFormat) { [weak self] b, _ in
            guard let self else { return }
            // Meter the first channel
            if let ch = b.floatChannelData?.pointee {
                var rms: Float = 0
                vDSP_rmsqv(ch, 1, &rms, vDSP_Length(b.frameLength))
                self.currentLevel = min(1, pow(rms, 0.5) * 2)
                // cheap “spectrum-like” bar (sample down)
                let buckets = self.latestSpectrum.count
                let stride = max(1, Int(b.frameLength) / buckets)
                for i in 0..<buckets { self.latestSpectrum[i] = abs(ch[i*stride]) }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // Connect using the explicit standardized format
    @MainActor
    private func attachAndConnectPlayerIfNeeded() {
        if !isPlayerAttached {
            audioEngine.attach(audioPlayer)
            isPlayerAttached = true
        }
        
        let mixer = audioEngine.mainMixerNode
        let mixerRate = mixer.outputFormat(forBus: 0).sampleRate
        
        guard mixerRate > 0, let processingFormat = getProcessingFormat(sampleRate: mixerRate) else {
            print("[Live] Failed to determine processing format or mixer rate is 0.")
            return
        }

        // Check if already connected with the correct format
        if audioPlayer.engine != nil && audioPlayer.outputFormat(forBus: 0) == processingFormat {
             // Already connected correctly
             return
        }
        
        // Disconnect if connected (potentially with the wrong format)
        if audioPlayer.engine != nil {
             audioEngine.disconnectNodeOutput(audioPlayer)
        }
        
        // Connect using the standardized format
        audioEngine.connect(audioPlayer, to: mixer, format: processingFormat)
        print("[Live] Connected player node with standardized format: \(processingFormat)")

        audioPlayer.volume = 1.0
        audioEngine.mainMixerNode.outputVolume = 1.0
    }
    
    @MainActor
    func debugPlaySine(_ seconds: Double = 2.0, freq: Double = 440) {
        attachAndConnectPlayerIfNeeded()
        
        // Use the format the player is connected with
        let fmt = audioPlayer.outputFormat(forBus: 0)
        if fmt.sampleRate == 0 { return }

        // Ensure engine is running before scheduling
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("[Live] Failed to start engine for sine wave: \(error)")
                return
            }
        }
        
        let frames = AVAudioFrameCount(seconds * fmt.sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
              let chs = buf.floatChannelData else { print("[Live] sine alloc fail"); return }

        buf.frameLength = frames
        let step = Float(2 * .pi * freq / fmt.sampleRate)
        var phase: Float = 0
        for f in 0..<Int(frames) {
            let s = sin(phase) * 0.2
            phase += step
            // Write to all channels (Stereo)
            for c in 0..<Int(fmt.channelCount) { chs[c][f] = s }
        }

        audioPlayer.scheduleBuffer(buf, at: nil, options: []) { print("[Live] sine done") }
        if !audioPlayer.isPlaying {
            audioPlayer.play()
        }
        print("[Live] sine scheduled \(frames) @\(Int(fmt.sampleRate))Hz, chs=\(fmt.channelCount)")
    }

    // MARK: Mic capture → convert → send

    private func processMicBuffer(_ buffer: AVAudioPCMBuffer) {
        guard !isMicMuted, (status == .connected || status == .permissionDenied), let converter = micInputConverter else { return }

        // Convert input to 16k/mono/Int16
        let outCap = AVAudioFrameCount(Double(buffer.frameLength) * captureFormat.sampleRate / buffer.format.sampleRate + 1)
        guard let out = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: outCap) else { return }

        var provided = false
        var err: NSError?
        _ = converter.convert(to: out, error: &err) { _, outStatus in
            defer { provided = true }
            if !provided {
                outStatus.pointee = .haveData
                return buffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }
        if err != nil {
            print("[Live] Mic conversion error: \(String(describing: err))")
            return
        }

        if let data = out.toPCM16Data() {
            Task { @MainActor in self.isSendingAudio = true }
            webSocketTask?.send(.data(data)) { [weak self] err in
                Task { @MainActor in
                    self?.isSendingAudio = false
                    // Start waiting for response only if send succeeded
                    if err == nil {
                         self?.isWaitingForResponse = true
                    }
                }
            }
        }
    }

    // MARK: Inbound audio → decode → resample → schedule

    private func handleIncomingAudio(_ data: Data) {
        // print("[Live] Incoming raw PCM data size: \(data.count) bytes")

        // 1. Decode PCM16 mono at 24kHz (Use expected format, not heuristic).
        guard let monoBuf = dataToPCMBuffer(data, format: expectedInboundFormat) else {
            // Error logged in helper
            return
        }

        // 2. Get the mixer’s sample rate ON MAIN (safe to read).
        let mixerRate = audioEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        if mixerRate == 0 {
             print("[Live] Mixer rate is 0. Cannot process audio.")
             return
        }

        // 3. Do ALL converter work on the playbackQueue.
        playbackQueue.async { [weak self] in
            guard let self else { return }
            if self.isShuttingDown { return }

            // Prepare (or reuse) the converter on THIS queue.
            self.preparePlaybackConverterIfNeeded_threadSafe(input: monoBuf.format, mixerRate: mixerRate)

            guard let converter = self.playbackConverter, !self.isShuttingDown else { return }

            // Keep a strong ref to the input buffer.
            let localMono = monoBuf
            var provided = false

            // 4. Convert the audio. We convert the whole chunk at once for efficiency.
            
            // Calculate required output capacity
            let ratio = converter.outputFormat.sampleRate / localMono.format.sampleRate
            let outCapacity = AVAudioFrameCount(Double(localMono.frameLength) * ratio) + 512 // Add padding

            guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: outCapacity) else { return }

            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                if provided {
                    outStatus.pointee = .noDataNow
                    return nil
                } else {
                    provided = true
                    outStatus.pointee = .haveData
                    return localMono
                }
            }

            if let error {
                print("[Live] convert error: \(error)")
                return
            }
            
            if status == .error {
                 print("[Live] convert status error.")
                 return
            }

            if out.frameLength > 0 {
                // Note: Mono to Stereo conversion is handled by the converter's channelMap.
                self.applyGain(out, 0.9)
                // 5. Schedule the converted buffer for playback.
                self.scheduleForPlayback(out)
            }
        }
    }

    private func preparePlaybackConverterIfNeeded_threadSafe(input: AVAudioFormat, mixerRate: Double) {
        // Get the standardized output format
        guard let out = getProcessingFormat(sampleRate: mixerRate) else { return }

        if playbackConverter == nil ||
           lastInboundPlaybackFormat != input ||
           playbackConverter?.outputFormat != out {

            print("[Live] Creating new playback converter from \(input) to \(out)")
            let conv = AVAudioConverter(from: input, to: out)
            conv?.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            conv?.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
            
            // Handle Mono (Input) to Stereo (Output) conversion efficiently
            if input.channelCount == 1 && out.channelCount == 2 {
                // Map input channel 0 to both output channels 0 and 1
                conv?.channelMap = [0, 0]
            }
            
            playbackConverter = conv
            lastInboundPlaybackFormat = input
        }
    }

    private func applyGain(_ buf: AVAudioPCMBuffer, _ g: Float) {
        guard let chs = buf.floatChannelData else { return }
        for c in 0..<Int(buf.format.channelCount) {
            var gain = g
            vDSP_vsmul(chs[c], 1, &gain, chs[c], 1, vDSP_Length(buf.frameLength))
        }
    }

    // Direct scheduling on MainActor with robust activation
    private func scheduleForPlayback(_ buffer: AVAudioPCMBuffer) {
        // Switch back to MainActor to interact with AVAudioEngine/AVAudioPlayerNode.
        Task { @MainActor in
            guard !isShuttingDown else { return }

            // Ensure connection is correct
            attachAndConnectPlayerIfNeeded()

            // Ensure the engine is running.
            if !audioEngine.isRunning {
                // If the engine isn't running, the session likely needs reconfiguration/reactivation
                do {
                    // Reassert category and activation before starting the engine
                    // This handles cases where the ViewModel might have changed it back to .playback
                    if audioSession.category != .playAndRecord || audioSession.mode != .voiceChat {
                         try audioSession.setCategory(.playAndRecord,
                                                    mode: .voiceChat,
                                                      options: [.defaultToSpeaker,.mixWithOthers, .allowAirPlay, .allowBluetoothHFP, .allowBluetoothA2DP])
                    }
                   
                    // Ensure activation before starting the engine.
                    try audioSession.setActive(true)
                    
                    try audioEngine.start()
                } catch {
                    print("[Live] Failed to start audio engine/session during playback: \(error)")
                    // If we can't start, we can't play this buffer.
                    return
                }
            }

            // Schedule the buffer directly.
            audioPlayer.scheduleBuffer(buffer)

            // Start the player if it's not already playing.
            if audioEngine.isRunning && !audioPlayer.isPlaying {
                audioPlayer.play()
            }
        }
    }

    // MARK: - Cleanup

    @MainActor
    private func cleanupAudioEngine() {
        isShuttingDown = true         // <- guard in-flight conversions
        audioPlayer.stop()
        if isMicrophoneAvailable {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }

        // Tear down graph
        if isPlayerAttached {
            audioEngine.disconnectNodeOutput(audioPlayer)
            audioEngine.detach(audioPlayer)
        }
        audioEngine.reset()
        isPlayerAttached = false

        // Clear converters on the dedicated queue to avoid races
        playbackQueue.sync {
            playbackConverter = nil
            lastInboundPlaybackFormat = nil
        }

        micInputConverter = nil
        isMicrophoneAvailable = false
        isMicMuted = true
        isShuttingDown = false        // ready for next start
        
        // Deactivate the session when fully done with this service.
        // This allows the ViewModel to successfully reconfigure it for playback.
        do {
            try audioSession.setActive(false)
            print("[Live] Audio session deactivated during cleanup.")
        } catch {
            print("[Live] Failed to deactivate audio session during cleanup: \(error)")
        }
    }
    
    // Helper method to decode PCM data using a specified format.
    private func dataToPCMBuffer(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        
        guard bytesPerFrame > 0 else { return nil }
        
        // Ensure data size is valid for the format
        if data.count % bytesPerFrame != 0 {
            print("[Live] Invalid PCM data size: \(data.count) bytes is not a multiple of frame size (\(bytesPerFrame)).")
            return nil
        }
        
        let frames = UInt32(data.count / bytesPerFrame)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        
        // Copy raw data into the buffer
        data.withUnsafeBytes { raw in
            let m = buf.audioBufferList.pointee.mBuffers
            if let dst = m.mData {
                memcpy(dst, raw.baseAddress!, data.count)
            }
        }
        return buf
    }

    // MARK: - Permissions

    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        #if os(visionOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: completion(true)
        case .denied: completion(false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in completion(granted) }
            }
        @unknown default: completion(false)
        }
        #else
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: completion(true)
        case .denied: completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in completion(granted) }
            }
        @unknown default: completion(false)
        }
        #endif
    }
}

// MARK: - Buffer Helpers

private extension AVAudioPCMBuffer {
    func toPCM16Data() -> Data? {
        guard format.commonFormat == .pcmFormatInt16 else { return nil }

        if format.isInterleaved {
            let m = audioBufferList.pointee.mBuffers
            guard let p = m.mData else { return nil }
            return Data(bytes: p, count: Int(m.mDataByteSize))
        } else {
            // Non-interleaved path (less common for PCM16 but handled for completeness)
            guard let ch = int16ChannelData else { return nil }
            let channels = Int(format.channelCount)
            let frames = Int(frameLength)
            let bytesPerSample = 2
            var out = Data(count: frames * channels * bytesPerSample)
            out.withUnsafeMutableBytes { raw in
                let dst = raw.bindMemory(to: Int16.self).baseAddress!
                for f in 0..<frames {
                    for c in 0..<channels {
                        dst[f * channels + c] = ch[c][f]
                    }
                }
            }
            return out
        }
    }
}
