//
//  Emitters.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 10/15/24.
//

import Foundation

struct Emitters:Identifiable,Equatable, Hashable,Encodable, Decodable {
    let id: String
    let timestamp: Date
    let senderId: String
    let senderName: String
    let emoji: Int
    let seatOrTheatre: Bool
}
