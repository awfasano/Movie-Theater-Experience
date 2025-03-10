//
//  TheatreVisibilityManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/10/25.
//

import Foundation

class TheatreVisibilityManager: ObservableObject {
    static let shared = TheatreVisibilityManager()
    @Published var isTheatreVisible = true
    
    private init() {}
}
