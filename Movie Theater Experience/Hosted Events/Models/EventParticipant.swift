//
//  EventParticipant.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import FirebaseFirestore
import simd

struct EventParticipant: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let userName: String
    let joinedAt: Date
    var tableNumber: Int?
    var seatIndex: Int?
    var role: ParticipantRole
    var isPresent: Bool = true
    var lastActivity: Date = Date()

    // Persona positioning
    var personaPosition: SIMD3<Float>?
    var personaRotation: simd_quatf?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case userName
        case joinedAt
        case tableNumber
        case seatIndex
        case role
        case isPresent
        case lastActivity
        case personaPositionX
        case personaPositionY
        case personaPositionZ
        case personaRotationX
        case personaRotationY
        case personaRotationZ
        case personaRotationW
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.userName = try container.decode(String.self, forKey: .userName)
        self.joinedAt = try container.decode(Date.self, forKey: .joinedAt)
        self.tableNumber = try container.decodeIfPresent(Int.self, forKey: .tableNumber)
        self.seatIndex = try container.decodeIfPresent(Int.self, forKey: .seatIndex)
        self.role = try container.decode(ParticipantRole.self, forKey: .role)
        self.isPresent = try container.decodeIfPresent(Bool.self, forKey: .isPresent) ?? true
        self.lastActivity = try container.decodeIfPresent(Date.self, forKey: .lastActivity) ?? Date()

        // Decode optional position components
        if let px = try container.decodeIfPresent(Float.self, forKey: .personaPositionX),
           let py = try container.decodeIfPresent(Float.self, forKey: .personaPositionY),
           let pz = try container.decodeIfPresent(Float.self, forKey: .personaPositionZ) {
            self.personaPosition = SIMD3<Float>(px, py, pz)
        } else {
            self.personaPosition = nil
        }

        // Decode optional rotation components
        if let rx = try container.decodeIfPresent(Float.self, forKey: .personaRotationX),
           let ry = try container.decodeIfPresent(Float.self, forKey: .personaRotationY),
           let rz = try container.decodeIfPresent(Float.self, forKey: .personaRotationZ),
           let rw = try container.decodeIfPresent(Float.self, forKey: .personaRotationW) {
            self.personaRotation = simd_quatf(ix: rx, iy: ry, iz: rz, r: rw)
        } else {
            self.personaRotation = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(userName, forKey: .userName)
        try container.encode(joinedAt, forKey: .joinedAt)
        try container.encodeIfPresent(tableNumber, forKey: .tableNumber)
        try container.encodeIfPresent(seatIndex, forKey: .seatIndex)
        try container.encode(role, forKey: .role)
        try container.encode(isPresent, forKey: .isPresent)
        try container.encode(lastActivity, forKey: .lastActivity)

        if let pos = personaPosition {
            try container.encode(pos.x, forKey: .personaPositionX)
            try container.encode(pos.y, forKey: .personaPositionY)
            try container.encode(pos.z, forKey: .personaPositionZ)
        }

        if let rot = personaRotation {
            try container.encode(rot.imag.x, forKey: .personaRotationX)
            try container.encode(rot.imag.y, forKey: .personaRotationY)
            try container.encode(rot.imag.z, forKey: .personaRotationZ)
            try container.encode(rot.real, forKey: .personaRotationW)
        }
    }
}

enum ParticipantRole: String, Codable {
    case host = "host"
    case participant = "participant"
    case moderator = "moderator"
}

extension EventParticipant {
    init(userId: String, userName: String, role: ParticipantRole) {
        self.id = nil
        self.userId = userId
        self.userName = userName
        self.joinedAt = Date()
        self.tableNumber = nil
        self.seatIndex = nil
        self.role = role
        self.isPresent = true
        self.lastActivity = Date()
        self.personaPosition = nil
        self.personaRotation = nil
    }
}
