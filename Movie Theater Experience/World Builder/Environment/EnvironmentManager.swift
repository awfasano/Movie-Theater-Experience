//
//  EnvironmentManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/16/25.
//

import Foundation
import FirebaseFirestore
import SwiftUI

@MainActor
class EnvironmentManager: ObservableObject {
    static let shared = EnvironmentManager()
    
    @Published var availableEnvironments: [EnvironmentData] = []
    @Published var isLoading = false

    /// Connect to your "worldbuilder" Firestore database
    private let db = Firestore.firestore(database: "worldbuilder")
    
    /// Load all public environments once
    func fetchAllEnvironments() async {
        guard availableEnvironments.isEmpty else { return }
        
        isLoading = true
        print("☁️ Fetching environments from Firestore…")
        
        do {
            let snapshot = try await db.collection("environments")
                .whereField("isPublic", isEqualTo: true)
                .getDocuments()
            
            let data = try snapshot.documents.compactMap { doc -> EnvironmentData? in
                do {
                    return try doc.data(as: EnvironmentData.self)
                } catch {
                    print("❌ Decoding failed for \(doc.documentID): \(error)")
                    return nil
                }
            }
            
            availableEnvironments = data
            print("✅ Loaded \(data.count) environments from Firestore.")
        }
        catch {
            print("🔥 Firestore error: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    /// Build a "fake" `EnvironmentData` instance to represent a basic preset
    func makeDefaultEnvironmentData(for preset: EnvironmentPreset) -> EnvironmentData {
        switch preset {
        case .defaultOutdoor:
            return EnvironmentData(
                id: "default_outdoor",
                name: "Basic Outdoor",
                category: "nature",
                description: "A simple outdoor sky and ground.",
                skybox: SkyboxSettings(
                    type: .simple,
                    assetUrl: nil,
                    thumbnailUrl: nil,
                    proceduralSettings: nil
                ),
                lighting: LightingSettings(
                    sunIntensity: 1_000,
                    sunColor: "#FFFFFF",
                    ambientIntensity: 0.2,
                    ambientColor: "#FFFFFF",
                    fogEnabled: false,
                    fogDensity: nil,
                    fogColor: nil
                ),
                ground: GroundSettings(
                    type: "plane",
                    terrainSize: .init(width: 50, depth: 50),
                    roughness: 0.8,
                    metallic: 0,
                    layers: nil
                ),
                audio: nil,
                weather: nil,
                tags: [],
                isPremium: false,
                thumbnailUrl: nil
            )
            
        case .defaultIndoor:
            return EnvironmentData(
                id: "default_indoor",
                name: "Basic Room",
                category: "indoor",
                description: "An empty, enclosed space.",
                skybox: SkyboxSettings(
                    type: .simple,
                    assetUrl: nil,
                    thumbnailUrl: nil,
                    proceduralSettings: nil
                ),
                lighting: LightingSettings(
                    sunIntensity: 500,
                    sunColor: "#FFE8CC",
                    ambientIntensity: 0.4,
                    ambientColor: "#FFFFFF",
                    fogEnabled: false,
                    fogDensity: nil,
                    fogColor: nil
                ),
                ground: GroundSettings(
                    type: "plane",
                    terrainSize: .init(width: 10, depth: 10),
                    roughness: 0.5,
                    metallic: 0,
                    layers: nil
                ),
                audio: nil,
                weather: nil,
                tags: [],
                isPremium: false,
                thumbnailUrl: nil
            )
        }
    }
}
