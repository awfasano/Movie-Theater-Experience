//
//  PlacedObject.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation

struct PlacedObject: Codable {
    let id: String
    let type: String
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var scale: SIMD3<Float>
    var properties: ObjectProperties?
    
    var dictionary: [String: Any] {
        return [
            "id": id,
            "type": type,
            "position": [position.x, position.y, position.z],
            "rotation": [rotation.real, rotation.imag.x, rotation.imag.y, rotation.imag.z],
            "scale": [scale.x, scale.y, scale.z]
        ]
    }
}
