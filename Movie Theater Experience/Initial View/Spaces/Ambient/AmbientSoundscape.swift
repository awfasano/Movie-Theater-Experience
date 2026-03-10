//
//  AmbientSoundscape.swift
//  Movie Theater Experience
//
//  Created for Ambient Focus Rooms feature.
//

import Foundation

enum AmbientSoundscapeType: String, CaseIterable, Codable {
    case rain
    case fireplace
    case ocean
    case forest
    case cafe
    case spaceHum

    var displayName: String {
        switch self {
        case .rain: return "Rain"
        case .fireplace: return "Fireplace"
        case .ocean: return "Ocean Waves"
        case .forest: return "Forest"
        case .cafe: return "Café"
        case .spaceHum: return "Deep Space"
        }
    }

    var iconName: String {
        switch self {
        case .rain: return "cloud.rain.fill"
        case .fireplace: return "flame.fill"
        case .ocean: return "water.waves"
        case .forest: return "leaf.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .spaceHum: return "sparkles"
        }
    }
}

struct AmbientSoundscapeInfo: Codable, Identifiable {
    var id: String { type.rawValue }
    let type: AmbientSoundscapeType
    let audioURL: String
    let isDefault: Bool
}
