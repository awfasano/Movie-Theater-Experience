//
//  WaveformViewModel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 6/23/25.
//

import Foundation
import QuartzCore
import SwiftUI

@MainActor
class WaveformViewModel: ObservableObject {
    
    // The waveform data that the View will display.
    @Published var audioLevels = [Float](repeating: 0, count: 50)
    
    // A reference to the service that plays the audio and provides the raw level data.
    var audioService: StorytellerAudioService?
    
    private var displayLink: CADisplayLink?
    
    /// Starts the display link timer to begin updating the waveform.
    func start() {
        // Stop any existing display link.
        stop()
        
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    /// Stops the display link timer.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    /// Applies smoothing to the provided level and shifts the sliding window.
    func apply(level: Float) {
        let previousLevel = audioLevels.last ?? 0
        let smoothedLevel = previousLevel * 0.6 + level * 0.4
        
        if !audioLevels.isEmpty {
            audioLevels.removeFirst()
        }
        audioLevels.append(smoothedLevel)
    }
    
    /// This function is called by the CADisplayLink every time the screen refreshes.
    @objc private func update() {
        guard let audioService = audioService else { return }
        
        // Read the latest audio level from the audio service.
        let latestLevel = audioService.getCurrentLevel()
        
        // Apply some smoothing to make the waveform look less jittery.
        apply(level: latestLevel)
    }
}
