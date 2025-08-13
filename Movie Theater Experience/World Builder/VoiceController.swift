//
//  VoiceController.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation

class VoiceController {
    var onTranscript: ((String) -> Void)?
    var onCommand: ((VoiceCommand) async -> Void)?
    
    func initialize() async {
        // Setup Gemini Live connection
    }
    
    func startListening() async {
        // Start voice recognition
    }
    
    func stopListening() async {
        // Stop voice recognition
    }
}
