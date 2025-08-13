//
//  WorldData.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation

// MARK: - Data Models
struct WorldData: Codable {
    let id: String
    let name: String
    let createdAt: Date
    let environment: EnvironmentPreset
    let objects: [PlacedObject]
}

