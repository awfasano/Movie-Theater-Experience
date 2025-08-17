//
//  GroundSettings.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/16/25.
//

import Foundation

struct AudioSettings: Codable {}
struct WeatherSettings: Codable {}

struct GroundSettings: Codable {
    struct TerrainSize: Codable {
        let width: Float
        let depth: Float
    }
    
    struct GroundLayer: Codable {
        let name: String
        let textureUrl: String
        let scale: Float
    }
    
    let type: String       // "terrain","plane","none"
    let terrainSize: TerrainSize?
    let roughness: Float?
    let metallic: Float?
    let layers: [GroundLayer]?
}

struct LightingSettings: Codable {
    let sunIntensity: Float
    let sunColor: String
    let ambientIntensity: Float
    let ambientColor: String
    let fogEnabled: Bool?
    let fogDensity: Float?
    let fogColor: String?
}
