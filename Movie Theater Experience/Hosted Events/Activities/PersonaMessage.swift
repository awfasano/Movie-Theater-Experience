//
//  PersonaMessage.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation

// Messaging for persona updates and game state

enum PersonaMessage: Codable {
    case positionUpdate(PersonaTablePosition)
    case tableAssignment(userId: String, tableNumber: Int, seatIndex: Int)
    case hostBroadcast(message: String, type: BroadcastType)
    case gameStateUpdate(GameState)
}

enum BroadcastType: String, Codable {
    case announcement = "announcement"
    case question = "question"
    case scoring = "scoring"
    case instruction = "instruction"
}
