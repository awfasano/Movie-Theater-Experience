//
//  SceneData.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 2/5/25.
//

import Foundation
import FirebaseFirestoreSwift
import FirebaseFirestore

struct SceneData: Identifiable, Codable {
    @DocumentID var id: String?   // auto-mapped from Firestore document ID
    var sceneName: String
    var lastModified: Timestamp
    var usdaURL: String         // URL to the USDA scene file
}
