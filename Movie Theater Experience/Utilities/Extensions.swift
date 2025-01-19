//
//  Extensions.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/9/24.
//

import Foundation
import SwiftUI

extension Color {
    static let accentColor = Color("AccentColor") // Assuming you've added this in your asset catalog
    // Or, using a specific color initializer
    static let accentColor2 = Color(red: 0.2, green: 0.8, blue: 0.6) // Example
}

extension Color {
    static let incomingBubble = Color(red: 0.2, green: 0.4, blue: 1) // A pleasant blue
    static let outgoingBubble = Color(red: 0.8, green: 0.8, blue: 0.8) // A light gray
}

extension float4x4 {
    init(lookAt from: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        let forward = normalize(target - from)
        let right = normalize(cross(up, forward))
        let upDirection = cross(forward, right)
        
        var matrix = matrix_identity_float4x4
        matrix.columns.0 = SIMD4<Float>(right.x, right.y, right.z, 0)
        matrix.columns.1 = SIMD4<Float>(upDirection.x, upDirection.y, upDirection.z, 0)
        matrix.columns.2 = SIMD4<Float>(forward.x, forward.y, forward.z, 0)
        matrix.columns.3 = SIMD4<Float>(from.x, from.y, from.z, 1)
        self = matrix
    }
}


extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))!
    }

    var monthAndYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: self)
    }

    var weekdaySymbol: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: self)
    }

    var day: Int {
        Calendar.current.component(.day, from: self)
    }

    var hourAndMinute: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    func daysInMonth() -> [Date] {
        let range = Calendar.current.range(of: .day, in: .month, for: self)!
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return range.compactMap { day -> Date? in
            var dateComponents = components
            dateComponents.day = day
            return Calendar.current.date(from: dateComponents)
        }
    }
}


