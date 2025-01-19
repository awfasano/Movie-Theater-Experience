//
//  TimeoutError.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/18/25.
//

import Foundation

struct TimeoutError: Error {
    let duration: TimeInterval
    
    var localizedDescription: String {
        return "Operation timed out after \(duration) seconds"
    }
}
