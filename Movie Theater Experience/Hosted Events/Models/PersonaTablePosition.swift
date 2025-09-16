//
//  PersonaTableParticipant.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import Foundation
import simd

struct PersonaTablePosition: Codable, Identifiable {
    let id = UUID()
    let userId: String
    let userName: String
    let tableNumber: Int
    let seatIndex: Int
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let timestamp: Date

    init(userId: String, userName: String, tableNumber: Int, seatIndex: Int, position: SIMD3<Float>, rotation: simd_quatf = simd_quatf()) {
        self.userId = userId
        self.userName = userName
        self.tableNumber = tableNumber
        self.seatIndex = seatIndex
        self.position = position
        self.rotation = rotation
        self.timestamp = Date()
    }
}
