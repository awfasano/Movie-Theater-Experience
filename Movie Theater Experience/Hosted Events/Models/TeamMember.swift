//
//  TeamMember.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/17/25.
//

import Foundation

// Models/TeamMember.swift
struct TeamMember: Identifiable, Codable {
    let id: String
    let userName: String
    var hasVoted: Bool = false
    var currentVote: Int?
    var score: Int = 0
    var isActive: Bool = true
    var avatarURL: String?
}
