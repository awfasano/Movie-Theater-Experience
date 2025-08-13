//
//  VoiceCommand.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation

// MARK: - Voice Command Structure
struct VoiceCommand {
    enum Action {
        case addObject
        case modifyEnvironment
        case deleteObject
        case moveObject
        case generateCustom
    }
    
    let action: Action
    let objectType: String
    let position: SIMD3<Float>?
    let properties: ObjectProperties?
    let targetId: String?
    let environmentType: EnvironmentPreset?
    let customDescription: String?
}
