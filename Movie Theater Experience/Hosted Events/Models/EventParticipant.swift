//
//  EventParticipant.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import Foundation
import FirebaseFirestore
import _FirebaseFirestore_Swift
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
}

enum ParticipantRole: String, Codable {
    case host = "host"
    case participant = "participant"
    case moderator = "moderator"
}
