//
//  CalendarEvent.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/26/24.
//


import Foundation

import Foundation

struct CalendarEvent: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var end: Date
    var description: String
    
    // Layout properties
    var column: Int = 0
    var totalColumns: Int = 1
}



