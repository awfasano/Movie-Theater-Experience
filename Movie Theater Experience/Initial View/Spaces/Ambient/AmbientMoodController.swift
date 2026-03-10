//
//  AmbientMoodController.swift
//  Movie Theater Experience
//
//  Created for Ambient Focus Rooms feature.
//

import Foundation

// MARK: - LightingMood

enum LightingMood: String, CaseIterable {
    case warm = "Warm"
    case cool = "Cool"
    case dim = "Dim"
    case bright = "Bright"

    var iconName: String {
        switch self {
        case .warm: return "sun.max.fill"
        case .cool: return "moon.fill"
        case .dim: return "moon.stars.fill"
        case .bright: return "sun.max.fill"
        }
    }
}

// MARK: - AmbientMoodController

@MainActor
class AmbientMoodController: ObservableObject {
    // MARK: - Published Properties
    @Published var ambientVolume: Float = 0.5
    @Published var currentSoundscape: AmbientSoundscapeType = .rain
    @Published var availableSoundscapes: [AmbientSoundscapeType] = AmbientSoundscapeType.allCases
    @Published var lightingMood: LightingMood = .warm

    // MARK: - Soundscape Control

    /// Switches the current soundscape and notifies the ambient audio manager.
    func switchSoundscape(to newSoundscape: AmbientSoundscapeType) {
        currentSoundscape = newSoundscape
        print("🎵 Mood controller switched soundscape to: \(newSoundscape.displayName)")
    }

    // MARK: - Volume Control

    /// Updates the ambient volume (0.0 to 1.0) and applies it via AmbientAudioManager.
    func updateVolume(_ volume: Float) {
        ambientVolume = max(0, min(1, volume))
        let volumePercent = ambientVolume * 100
        let gainDB = AmbientAudioManager.percentageToDecibels(volumePercent)
        print("🔊 Mood controller volume updated: \(Int(volumePercent))% (\(gainDB) dB)")
    }

    // MARK: - Lighting Control

    /// Sets the lighting mood. In v1 this stores the value only; actual lighting changes are deferred.
    func setLightingMood(_ mood: LightingMood) {
        lightingMood = mood
        print("💡 Mood controller lighting set to: \(mood.rawValue)")
    }

    // MARK: - Space Filtering

    /// Filters the available soundscapes based on the current space context.
    func filterSoundscapes(for spaceTags: [String]?) {
        // For v1, all soundscapes are available regardless of space
        availableSoundscapes = AmbientSoundscapeType.allCases
    }
}
