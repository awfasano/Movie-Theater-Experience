import AVFoundation
import RealityKit

class SpatialAudioManager: ObservableObject {
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var environmentNode: AVAudioEnvironmentNode
    private var speakerNodes: [String: AVAudioEnvironmentNode] = [:]
    private var isConfigured = false
    
    init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        environmentNode = AVAudioEnvironmentNode()
        
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        // Configure audio session first
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowBluetoothA2DP, .allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
            return
        }
        
        // Attach basic nodes
        audioEngine.attach(playerNode)
        audioEngine.attach(environmentNode)
        
        // Set up default routing through environment node
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        if let format = format {
            audioEngine.connect(playerNode, to: environmentNode, format: format)
            audioEngine.connect(environmentNode, to: audioEngine.mainMixerNode, format: format)
        }
        
        // Prepare and start the engine
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isConfigured = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func configureSpeakersFromTheater(_ theatreEntity: Entity) {
        guard isConfigured else {
            print("Audio engine not properly configured")
            return
        }
        
        // Stop the engine before reconfiguring
        audioEngine.stop()
        
        // Clear existing speaker nodes
        for node in speakerNodes.values {
            audioEngine.detach(node)
        }
        speakerNodes.removeAll()
        
        // Find all speaker entities
        let speakerEntities = findSpeakerEntities(in: theatreEntity)
        print("Found \(speakerEntities.count) speaker entities")
        
        // Create audio nodes for each speaker
        for speaker in speakerEntities {
            let speakerNode = AVAudioEnvironmentNode()
            audioEngine.attach(speakerNode)
            
            let position = speaker.transform.translation
            speakerNode.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
            speakerNode.reverbBlend = 0.5
            
            speakerNodes[speaker.name] = speakerNode
            
            // Connect through the environment node
            if let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) {
                audioEngine.connect(environmentNode, to: speakerNode, format: format)
                audioEngine.connect(speakerNode, to: audioEngine.mainMixerNode, format: format)
            }
        }
        
        // Prepare and restart the engine
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to restart audio engine after configuring speakers: \(error)")
        }
    }
    
    private func findSpeakerEntities(in entity: Entity) -> [Entity] {
        var speakers: [Entity] = []
        
        // Check if the current entity is a speaker
        if entity.name.lowercased().contains("speaker") {
            print("Found speaker: \(entity.name)")
            speakers.append(entity)
        }
        
        // Recursively check children
        for child in entity.children {
            speakers.append(contentsOf: findSpeakerEntities(in: child))
        }
        
        return speakers
    }
    
    func configureAudioForVideo(player: AVPlayer?) {
        guard let player = player, isConfigured else { return }
        
        // Stop the engine temporarily
        audioEngine.stop()
        
        do {
            // Make sure audio session is still active
            if !AVAudioSession.sharedInstance().isOtherAudioPlaying {
                try AVAudioSession.sharedInstance().setActive(true)
            }
            
            if let playerItem = player.currentItem {
                // Create an audio mix
                let audioMix = AVMutableAudioMix()
                playerItem.audioMix = audioMix
                
                // Set up audio format
                if let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) {
                    // Reconnect nodes with the new format
                    audioEngine.connect(playerNode, to: environmentNode, format: format)
                    
                    // Connect to speakers if available, otherwise to main mixer
                    if speakerNodes.isEmpty {
                        audioEngine.connect(environmentNode, to: audioEngine.mainMixerNode, format: format)
                    } else {
                        for speakerNode in speakerNodes.values {
                            audioEngine.connect(environmentNode, to: speakerNode, format: format)
                            audioEngine.connect(speakerNode, to: audioEngine.mainMixerNode, format: format)
                        }
                    }
                }
            }
            
            // Prepare and restart the engine
            audioEngine.prepare()
            try audioEngine.start()
            
        } catch {
            print("Failed to configure spatial audio for video: \(error)")
        }
    }
    
    func updateSpeakerPositions(_ theatreEntity: Entity) {
        let speakerEntities = findSpeakerEntities(in: theatreEntity)
        
        for speaker in speakerEntities {
            if let node = speakerNodes[speaker.name] {
                let position = speaker.transform.translation
                node.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
            }
        }
    }
    
    func cleanup() {
        playerNode.stop()
        audioEngine.stop()
        
        // Clean up speaker nodes
        for node in speakerNodes.values {
            audioEngine.detach(node)
        }
        speakerNodes.removeAll()
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        isConfigured = false
    }
}
