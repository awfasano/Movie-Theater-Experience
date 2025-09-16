//
//  TableLayoutCalculator.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import Foundation
import simd

struct TableLayoutCalculator {
    static func calculateTablePositions(for layoutType: TableLayoutType, maxTables: Int) -> [Int: SIMD3<Float>] {
        switch layoutType {
        case .circular:
            return calculateCircularLayout(maxTables: maxTables)
        case .classroom:
            return calculateClassroomLayout(maxTables: maxTables)
        case .theater:
            return calculateTheaterLayout(maxTables: maxTables)
        }
    }
    
    static func calculateSeatPositions(around tablePosition: SIMD3<Float>, maxSeats: Int) -> [SIMD3<Float>] {
        let radius: Float = 1.0
        return (0..<maxSeats).map { seatIndex in
            let angle = Float(seatIndex) * (2.0 * .pi / Float(maxSeats))
            return SIMD3<Float>(
                tablePosition.x + radius * cos(angle),
                tablePosition.y,
                tablePosition.z + radius * sin(angle)
            )
        }
    }
    
    static func calculateSeatRotation(tablePosition: SIMD3<Float>, seatPosition: SIMD3<Float>) -> simd_quatf {
        // Calculate rotation to face the table center
        let direction = normalize(tablePosition - seatPosition)
        let angle = atan2(direction.x, direction.z)
        return simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
    }
    
    // Example layouts (simple versions)
    private static func calculateCircularLayout(maxTables: Int) -> [Int: SIMD3<Float>] {
        let radius: Float = 3.0
        return (0..<maxTables).reduce(into: [Int: SIMD3<Float>]()) { dict, index in
            let angle = Float(index) * (2.0 * .pi / Float(maxTables))
            dict[index + 1] = SIMD3<Float>(radius * cos(angle), 0.0, radius * sin(angle))
        }
    }
    
    private static func calculateClassroomLayout(maxTables: Int) -> [Int: SIMD3<Float>] {
        // Arrange in rows
        let rows = Int(ceil(sqrt(Double(maxTables))))
        let cols = Int(ceil(Double(maxTables) / Double(rows)))
        var positions: [Int: SIMD3<Float>] = [:]
        var count = 1
        for row in 0..<rows {
            for col in 0..<cols {
                if count > maxTables { break }
                positions[count] = SIMD3<Float>(Float(col) * 2.0, 0, Float(-row) * 2.0)
                count += 1
            }
        }
        return positions
    }
    
    private static func calculateTheaterLayout(maxTables: Int) -> [Int: SIMD3<Float>] {
        // Line up facing a stage
        return (1...maxTables).reduce(into: [Int: SIMD3<Float>]()) { dict, i in
            dict[i] = SIMD3<Float>(Float(i - 1) * 2.0 - Float(maxTables - 1), 0, -4.0)
        }
    }
}

