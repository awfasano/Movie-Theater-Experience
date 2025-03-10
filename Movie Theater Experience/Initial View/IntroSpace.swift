//
//  asdfasdf.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 2/5/25.
//

import Foundation


struct IntroSpace: Identifiable {
    let id: Int
    let name: String
    let lastModified: Date
    let currentOccupancy: Int
    let maxOccupancy: Int
    
    var occupancyPercentage: Float {
        Float(currentOccupancy) / Float(maxOccupancy)
    }
}
