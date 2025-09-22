//
//  PersonaTableParticipant.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import simd

struct PersonaTablePosition: Codable, Identifiable {
    let id: UUID
    let userId: String
    let userName: String
    let tableNumber: Int
    let seatIndex: Int
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case userName
        case tableNumber
        case seatIndex
        case positionX
        case positionY
        case positionZ
        case rotationX
        case rotationY
        case rotationZ
        case rotationW
        case timestamp
    }

    init(id: UUID = UUID(), userId: String, userName: String, tableNumber: Int, seatIndex: Int, position: SIMD3<Float>, rotation: simd_quatf = simd_quatf(), timestamp: Date = Date()) {
        self.id = id
        self.userId = userId
        self.userName = userName
        self.tableNumber = tableNumber
        self.seatIndex = seatIndex
        self.position = position
        self.rotation = rotation
        self.timestamp = timestamp
    }

    init(userId: String, userName: String, tableNumber: Int, seatIndex: Int, position: SIMD3<Float>, rotation: simd_quatf = simd_quatf()) {
        self.init(id: UUID(), userId: userId, userName: userName, tableNumber: tableNumber, seatIndex: seatIndex, position: position, rotation: rotation, timestamp: Date())
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let userId = try container.decode(String.self, forKey: .userId)
        let userName = try container.decode(String.self, forKey: .userName)
        let tableNumber = try container.decode(Int.self, forKey: .tableNumber)
        let seatIndex = try container.decode(Int.self, forKey: .seatIndex)
        let px = try container.decode(Float.self, forKey: .positionX)
        let py = try container.decode(Float.self, forKey: .positionY)
        let pz = try container.decode(Float.self, forKey: .positionZ)
        let rx = try container.decode(Float.self, forKey: .rotationX)
        let ry = try container.decode(Float.self, forKey: .rotationY)
        let rz = try container.decode(Float.self, forKey: .rotationZ)
        let rw = try container.decode(Float.self, forKey: .rotationW)
        let timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()

        self.id = id
        self.userId = userId
        self.userName = userName
        self.tableNumber = tableNumber
        self.seatIndex = seatIndex
        self.position = SIMD3<Float>(px, py, pz)
        self.rotation = simd_quatf(ix: rx, iy: ry, iz: rz, r: rw)
        self.timestamp = timestamp
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(userName, forKey: .userName)
        try container.encode(tableNumber, forKey: .tableNumber)
        try container.encode(seatIndex, forKey: .seatIndex)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)
        try container.encode(position.z, forKey: .positionZ)
        try container.encode(rotation.imag.x, forKey: .rotationX)
        try container.encode(rotation.imag.y, forKey: .rotationY)
        try container.encode(rotation.imag.z, forKey: .rotationZ)
        try container.encode(rotation.real, forKey: .rotationW)
        try container.encode(timestamp, forKey: .timestamp)
    }
}
