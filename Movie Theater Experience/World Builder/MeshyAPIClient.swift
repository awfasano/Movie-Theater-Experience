//
//  MeshyAPIClient.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation

class MeshyAPIClient {
    func generateModel(from description: String) async -> URL {
        // Call Meshy API
        return URL(string: "https://example.com/model.usdz")!
    }
}
