//
//  LiveStorytellerService.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 6/21/25.
//  Fully revised 26 Jun 25
//

private struct StorytellerConfig: Codable {
    let voice: String
    let instruction: String
}


import Foundation
@preconcurrency import AVFoundation
import Accelerate                              // vDSP_rmsqv, vDSP_Length
import Combine


@MainActor
final class LiveStorytellerService: ObservableObject {

    // MARK: – Public status --------------------------------------------------
    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case error(String)
    }
    @Published private(set) var status: Status = .idle

    // MARK: – WebSocket + audio engine --------------------------------------
    private var webSocketTask: URLSessionWebSocketTask?
    private var voice: String = "Zephyr" // Default value
    private var instruction: String = "You are a helpful assistant." // Default value
    
    private var task: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)
    
    // MARK: - Public Properties (for UI updates)
    // Use Combine publishers to notify the ViewModel of new data.
    let audioDataPublisher = PassthroughSubject<Data, Never>()
    let transcriptPublisher = PassthroughSubject<String, Never>()
    
    private let audioSession  = AVAudioSession.sharedInstance()
    private let audioEngine   = AVAudioEngine()
    private let audioPlayer   = AVAudioPlayerNode()

    // Mic → 16-k Hz converter (needed on VisionOS / iOS)
    private var audioConverter: AVAudioConverter?
    private let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                sampleRate: 16_000,
                                                channels: 1,
                                                interleaved: true)!

    private var playbackFormat: AVAudioFormat?   // cached mixer format
    
    // MARK: – Audio metering (UI pulls these) --------------------------------
    private var currentLevel:   Float   = 0
    private var latestSpectrum: [Float] = Array(repeating: 0, count: 128)

    func getCurrentLevel() -> Float         { currentLevel }
    func getSpectrum()     -> [Float]       { latestSpectrum }

    /// Establishes the WebSocket connection, sends the configuration, and starts listening.
    func connectAndStart(urlString: String) {
        guard let url = URL(string: urlString) else {
            status = .error("Invalid WebSocket URL"); return
        }

        disconnect()
        
        status = .connecting
        print("[Live] Starting connection...")

        setupAudioEngine()
        
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        
        // Start listening for server messages.
        listenForMessages()
        
        // Open the connection.
        webSocketTask?.resume()
        
        // **DEADLOCK FIX**: Send the configuration immediately after resuming the task.
        // Do NOT wait for a message from the server first.
        sendConfig()
    }
    
    private func setupAudioEngine() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: .defaultToSpeaker)
            try audioSession.setActive(true)
        } catch {
            status = .error("Audio session error: \(error.localizedDescription)")
            return
        }

        audioEngine.attach(audioPlayer)
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: nil)

        do {
            audioEngine.prepare()
            try audioEngine.start()
            audioPlayer.play()
            startMicrophone() // Mic tap starts after engine is running
        } catch {
            status = .error("Audio engine error: \(error.localizedDescription)")
            disconnect()
        }
    }
    
    
    /// A recursive function that continuously listens for the next message from the server.
    private func listenForMessages() {
           webSocketTask?.receive { result in
               Task { @MainActor [weak self] in
                   guard let self = self else { return }

                   switch result {
                   case .success(let message):
                       // We are now safely on the Main Actor.
                       if self.status == .connecting {
                           self.status = .connected
                           print("[Live] Connection established.")
                       }

                       switch message {
                       case .string(let text):
                           self.transcriptPublisher.send(text)
                       case .data(let data):
                           self.handleIncomingPCM(data)
                       @unknown default:
                           break
                       }
                       // Recursively call listen for the next message.
                       self.listenForMessages()

                   case .failure(let error):
                       if (error as NSError).code != NSURLErrorCancelled {
                           print("[WS] Receive error: \(error.localizedDescription)")
                           self.disconnect()
                       }
                   }
               }
           }
       }
    
    
    /// Encodes the stored configuration into JSON and sends it as a string message.
    private func sendConfig() {
        let config = StorytellerConfig(voice: self.voice, instruction: self.instruction)
        
        do {
            let jsonData = try JSONEncoder().encode(config)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            
            webSocketTask?.send(.string(jsonString)) { error in
                if let error {
                    print("LiveStorytellerService: Error sending configuration: \(error)")
                    // If sending the config fails, we can't proceed.
                    Task { await self.disconnect() }
                } else {
                    print("LiveStorytellerService: Configuration sent successfully.")
                }
            }
        } catch {
            print("LiveStorytellerService: Failed to encode configuration: \(error)")
            Task { await self.disconnect() }
        }
    }

    

    // MARK: – Open WebSocket, start engine, attach player
    private func setupAndConnect(urlString: String) {
        // — 0. Validate URL ----------------------------------------------------
        guard let url = URL(string: urlString) else {
            status = .error("Invalid WebSocket URL")
            return
        }

        // — 1. Configure AVAudioSession ---------------------------------------
        do {
            try audioSession.setCategory(.playAndRecord,
                                         mode: .voiceChat,
                                         options: .defaultToSpeaker)
            try audioSession.setActive(true)
        } catch {
            status = .error("Audio-session error: \(error.localizedDescription)")
            return
        }

        // — 2. Prepare AVAudioEngine graph ------------------------------------
        audioEngine.attach(audioPlayer)
        
        // Let the engine determine the connection format.
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: nil)

        do {
            audioEngine.prepare()
            try audioEngine.start()
            audioPlayer.play()
        } catch {
            status = .error("Audio-engine error: \(error.localizedDescription)")
            return
        }

        // — 3. Open WebSocket --------------------------------------------------
        status = .connecting
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()

        listenForMessages()
        startMicrophone()
        print("[Live] WebSocket connecting …")
    }
    
    func configure(voice: String, instruction: String) {
        self.voice = voice
        self.instruction = instruction
    }


    func disconnect() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            audioPlayer.stop()
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        try? audioSession.setActive(false)
        if status != .idle {
             status = .idle
             print("[Live] Disconnected.")
        }
    }

    // MARK: – Play incoming PCM + compute meters ----------------------------
    // MARK: – Play incoming PCM + compute meters --------------------------------
    private func handleIncomingPCM(_ data: Data) {
        //-----------------------------------------------------------------------
        // 0)  Define the source format (what Gemini sends)
        //-----------------------------------------------------------------------
        guard let srcFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: 24_000,
                                            channels: 1,
                                            interleaved: false),
              let srcBuf    = data.toPCMBuffer(format: srcFormat)
        else { return }

        //-----------------------------------------------------------------------
        // 1)  Get (or cache) the *destination* format – whatever the main mixer
        //     is actually using on this device / simulator (e.g. 48-k Hz stereo
        //     Float32).  We query once and keep it.
        //-----------------------------------------------------------------------
        let dstFormat: AVAudioFormat
        if let cached = self.playbackFormat {         // <- add this stored prop:
            dstFormat = cached                        //    `private var playbackFormat: AVAudioFormat?`
        } else {
            dstFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
            self.playbackFormat = dstFormat
        }

        //-----------------------------------------------------------------------
        // 2)  Convert source → destination with AVAudioConverter  ̄\_(ツ)_/
        //-----------------------------------------------------------------------
        guard let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFormat,
                                            frameCapacity: AVAudioFrameCount(
                                                Double(srcBuf.frameLength)
                                              * dstFormat.sampleRate
                                              / srcFormat.sampleRate))
        else { return }

        let converter = AVAudioConverter(from: srcFormat, to: dstFormat)!
        var error: NSError?
        converter.convert(to: dstBuf, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return srcBuf
        }
        if let error { print("[Live] convert error:", error); return }

        //-----------------------------------------------------------------------
        // 3)  Queue for playback  (formats now *always* match the player node)
        //-----------------------------------------------------------------------
        audioPlayer.scheduleBuffer(dstBuf)

        //-----------------------------------------------------------------------
        // 4)  Re-derive meters from the **converted** float data --------------
        //-----------------------------------------------------------------------
        guard let floatPtr = dstBuf.floatChannelData?.pointee else { return }
        let frames = Int(dstBuf.frameLength)

        // RMS loudness
        var rms: Float = 0
        vDSP_rmsqv(floatPtr, 1, &rms, vDSP_Length(frames))
        let level = pow(rms, 0.5) * 2                                   // boost

        // 128-bucket snapshot
        let bucketCount = latestSpectrum.isEmpty ? 128 : latestSpectrum.count

        var snap = Array(repeating: 0.0 as Float,   // 👈 Float, not Int
                         count: bucketCount)

        let stride = max(1, frames / bucketCount)   // avoids divide-by-zero
        for i in 0..<bucketCount {
            snap[i] = fabsf(floatPtr[i * stride])
        }

        // Commit on MainActor so UI can read safely
        Task { @MainActor in
            self.currentLevel   = level
            self.latestSpectrum = snap              // always `bucketCount` floats
        }
    }


    // MARK: – Mic capture & stream ------------------------------------------
    private func startMicrophone() {
            let inputNode   = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard inputFormat.sampleRate  > 0,
                  inputFormat.channelCount > 0
            else {
                status = .error("No valid microphone.")
                return
            }

            audioConverter = AVAudioConverter(from: inputFormat, to: recordingFormat)

            inputNode.installTap(onBus: 0,
                                 bufferSize: 1024,
                                 format: inputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                // --- SOLUTION: Safely capture the web socket task ---
                // Create a strong local reference. If `disconnect()` was called,
                // this will be nil and we will safely exit the closure.
                guard let task = self.webSocketTask,
                      let converter = self.audioConverter
                else { return }

                // Convert to 16-k Hz Int16 mono
                let frameCap = AVAudioFrameCount(self.recordingFormat.sampleRate
                                                 * Double(buffer.frameLength)
                                                 / inputFormat.sampleRate)

                guard let convBuf = AVAudioPCMBuffer(pcmFormat: recordingFormat,
                                                     frameCapacity: frameCap)
                else { return }

                var error: NSError?
                converter.convert(to: convBuf, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                if error != nil { return }

                if let d = convBuf.toData() {
                    // Use the safely captured `task` variable, NOT `self.webSocketTask`.
                    // This is now thread-safe.
                    task.send(.data(d)) { err in
                        if let err { print("[WS] send error:", err.localizedDescription) }
                    }
                }
            }

            status = .connected
            print("[Live] Mic tap installed; streaming.")
        }

    // MARK: – Text / mic helpers --------------------------------------------
    func send(text: String) {
        webSocketTask?.send(.string(text)) { err in
            if let err { print("[WS] text send error:", err) }
        }
    }

    func setMic(active: Bool) {
        audioEngine.inputNode.volume = active ? 1 : 0      // simple software mute
    }
}

// MARK: – Buffer/Data helpers -----------------------------------------------
extension AVAudioPCMBuffer {
    func toData() -> Data? {
        guard let chData = int16ChannelData else { return nil }
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        return Data(bytes: chData[0], count: Int(frameLength) * Int(bytesPerFrame))
    }
}

extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        let frames = UInt32(count) / bytesPerFrame
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames

        guard let dst = buf.int16ChannelData else { return nil }
        _ = withUnsafeBytes { srcPtr in
            guard let src = srcPtr.baseAddress else { return }
            dst[0].assign(from: src.assumingMemoryBound(to: Int16.self),
                          count: Int(frames))
        }
        return buf
    }
}

