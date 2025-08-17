//
//  WorldBuilderFirestoreManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/16/25.
//

import Foundation
import FirebaseFirestore

final class WorldBuilderFirestoreManager {
    static let shared = WorldBuilderFirestoreManager()

    let db: Firestore

    private init() {
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.firestoreDatabase = "worldbuilder"      // <— using your custom DB
        let firestore = Firestore.firestore()
        firestore.settings = settings
        self.db = firestore
    }

    // MARK: - Load Environments
    func fetchEnvironments() async throws -> [EnvironmentData] {
        let snapshot = try await db.collection("environments")
            .whereField("isPublic", isEqualTo: true)
            .getDocuments()

        return try snapshot.documents.compactMap { doc in
            let data = doc.data()
            let json = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(EnvironmentData.self, from: json)
        }
    }

    // MARK: - Load Objects
    func fetchObjects() async throws -> [ObjectData] {
        let snapshot = try await db.collection("objects").getDocuments()
        return snapshot.documents.compactMap { ObjectData(from: $0.data()) }
    }

    // MARK: - Load Textures
    func fetchTextures() async throws -> [TextureData] {
        let snapshot = try await db.collection("textures").getDocuments()
        return snapshot.documents.compactMap { TextureData(from: $0.data()) }
    }
}
