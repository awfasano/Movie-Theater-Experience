import Foundation
import simd

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
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case id, type, position, rotation, scale, properties
    }
    
    // Custom encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        
        // Encode SIMD3<Float> as array
        let positionArray = [position.x, position.y, position.z]
        try container.encode(positionArray, forKey: .position)
        
        // Encode simd_quatf as array [real, imag.x, imag.y, imag.z]
        let rotationArray = [rotation.real, rotation.imag.x, rotation.imag.y, rotation.imag.z]
        try container.encode(rotationArray, forKey: .rotation)
        
        // Encode SIMD3<Float> as array
        let scaleArray = [scale.x, scale.y, scale.z]
        try container.encode(scaleArray, forKey: .scale)
        
        try container.encodeIfPresent(properties, forKey: .properties)
    }
    
    // Custom decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        
        // Decode position from array
        let positionArray = try container.decode([Float].self, forKey: .position)
        guard positionArray.count == 3 else {
            throw DecodingError.dataCorruptedError(forKey: .position, in: container, debugDescription: "Position array must have 3 elements")
        }
        position = SIMD3<Float>(positionArray[0], positionArray[1], positionArray[2])
        
        // Decode rotation from array
        let rotationArray = try container.decode([Float].self, forKey: .rotation)
        guard rotationArray.count == 4 else {
            throw DecodingError.dataCorruptedError(forKey: .rotation, in: container, debugDescription: "Rotation array must have 4 elements")
        }
        rotation = simd_quatf(real: rotationArray[0], imag: SIMD3<Float>(rotationArray[1], rotationArray[2], rotationArray[3]))
        
        // Decode scale from array
        let scaleArray = try container.decode([Float].self, forKey: .scale)
        guard scaleArray.count == 3 else {
            throw DecodingError.dataCorruptedError(forKey: .scale, in: container, debugDescription: "Scale array must have 3 elements")
        }
        scale = SIMD3<Float>(scaleArray[0], scaleArray[1], scaleArray[2])
        
        properties = try container.decodeIfPresent(ObjectProperties.self, forKey: .properties)
    }
    
    // Convenience initializer for creating new objects
    init(id: String, type: String, position: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>, properties: ObjectProperties? = nil) {
        self.id = id
        self.type = type
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.properties = properties
    }
}
