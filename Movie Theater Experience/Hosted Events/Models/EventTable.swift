//
//  Fixed EventTable.swift
//  Movie Theater Experience
//
//  Removes nested arrays that cause Firestore errors

import Foundation
import FirebaseFirestore
import simd

// MARK: - Helper struct to avoid SIMD encoding issues
struct Position3D: Codable {
    var x: Float
    var y: Float
    var z: Float
    
    init(_ simd: SIMD3<Float>) {
        self.x = simd.x
        self.y = simd.y
        self.z = simd.z
    }
    
    var simd3: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}

// MARK: - Fixed EventTable
public struct EventTable: Identifiable, Codable {
    @DocumentID public var id: String?
    let tableNumber: Int
    var tableName: String?
    var participants: [String] = []
    let maxSeats: Int
    var currentScore: Int = 0
    var teamName: String?

    // FaceTime link for this table (real URL from Apple FaceTime Links)
    var faceTimeLinkURL: String?

    // FIXED: Use flattened position instead of SIMD3 directly
    var tablePosition: Position3D

    // FIXED: Instead of [SIMD3<Float>], use a dictionary to avoid nested arrays
    var seatPositions: [String: Position3D] // "0": position, "1": position, etc.

    var availableSeats: Int { maxSeats - participants.count }
    var isFull: Bool { participants.count >= maxSeats }
    
    // MARK: - Initializer that converts from SIMD3 arrays
    init(tableNumber: Int, tableName: String? = nil, participants: [String] = [],
         maxSeats: Int, currentScore: Int = 0, teamName: String? = nil,
         tablePosition: SIMD3<Float>, seatPositions: [SIMD3<Float>],
         faceTimeLinkURL: String? = nil) {

        self.tableNumber = tableNumber
        self.tableName = tableName
        self.participants = participants
        self.maxSeats = maxSeats
        self.currentScore = currentScore
        self.teamName = teamName
        self.faceTimeLinkURL = faceTimeLinkURL
        self.tablePosition = Position3D(tablePosition)

        // Convert array to dictionary to avoid nested arrays
        var seatMap: [String: Position3D] = [:]
        for (index, position) in seatPositions.enumerated() {
            seatMap["\(index)"] = Position3D(position)
        }
        self.seatPositions = seatMap
    }
    
    // MARK: - Helper methods
    func getSeatPositions() -> [SIMD3<Float>] {
        let sortedKeys = seatPositions.keys.sorted { Int($0) ?? 0 < Int($1) ?? 0 }
        return sortedKeys.compactMap { seatPositions[$0]?.simd3 }
    }
    
    func getSeatPosition(at index: Int) -> SIMD3<Float>? {
        return seatPositions["\(index)"]?.simd3
    }
    
    mutating func setSeatPosition(at index: Int, position: SIMD3<Float>) {
        seatPositions["\(index)"] = Position3D(position)
    }
}
