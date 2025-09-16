//
//  EventTable.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import Foundation
import FirebaseFirestore
import _FirebaseFirestore_Swift
import simd

struct EventTable: Identifiable, Codable {
    @DocumentID var id: String?
    let tableNumber: Int
    var tableName: String?
    var participants: [String] = []
    let maxSeats: Int
    var currentScore: Int = 0
    var teamName: String?

    // 3D positioning
    var tablePosition: SIMD3<Float>
    var seatPositions: [SIMD3<Float>]

    var availableSeats: Int { maxSeats - participants.count }
    var isFull: Bool { participants.count >= maxSeats }
}
