//
//  SeatPosition.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 4/6/25.
//

import Foundation

struct SeatPosition: Identifiable, Codable, Equatable {
    var id: String // seat_1, seat_2, etc.
    var x: Double
    var y: Double
    var isAvailable: Bool = true
    var label: String?
    
    // Computed property for SwiftUI positioning (not stored in Firestore)
    var position: CGPoint {
        CGPoint(x: x, y: y)
    }
    
    // Equatable conformance
    static func == (lhs: SeatPosition, rhs: SeatPosition) -> Bool {
        return lhs.id == rhs.id
    }
}
