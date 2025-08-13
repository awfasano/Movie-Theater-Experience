//
//  EnvironmentalPresets.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation

enum EnvironmentPreset: String, Codable, CaseIterable {
    case defaultOutdoor = "outdoor"
    case forest = "forest"
    case desert = "desert"
    case snow = "snow"
    case indoor = "indoor"
    case space = "space"
    
    var lightIntensity: Float {
        switch self {
        case .defaultOutdoor, .desert: return 1000
        case .forest: return 800
        case .snow: return 1200
        case .indoor: return 500
        case .space: return 200
        }
    }
    
    var lightColor: UIColor {
        switch self {
        case .defaultOutdoor: return .white
        case .forest: return UIColor(red: 0.9, green: 0.95, blue: 0.8, alpha: 1)
        case .desert: return UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1)
        case .snow: return UIColor(red: 0.9, green: 0.95, blue: 1, alpha: 1)
        case .indoor: return UIColor(red: 1, green: 0.95, blue: 0.9, alpha: 1)
        case .space: return UIColor(red: 0.8, green: 0.8, blue: 1, alpha: 1)
        }
    }
    
    var groundColor: UIColor {
        switch self {
        case .defaultOutdoor, .forest: return UIColor(red: 0.3, green: 0.5, blue: 0.2, alpha: 1)
        case .desert: return UIColor(red: 0.9, green: 0.7, blue: 0.4, alpha: 1)
        case .snow: return .white
        case .indoor: return UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        case .space: return .black
        }
    }
}
