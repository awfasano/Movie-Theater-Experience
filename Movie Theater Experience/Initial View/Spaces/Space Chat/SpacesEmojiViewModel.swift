
//
//  SpacesEmojiViewModel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/10/25.
//

import Foundation
import SwiftUI

@MainActor
class SpacesEmojiViewModel: ObservableObject {
    @Published var isOnCooldown = false
    @Published var isEmitting = false
    @Published var activeEmoji: String? = nil
    
    // Static emoji types to avoid recreation
    let emojiTypes: [EmojiType] = [
        EmojiType(unicode: "❤️", number: 0, assetName: "heart", isLooping: false),
        EmojiType(unicode: "😢", number: 1, assetName: "crying", isLooping: false),
        EmojiType(unicode: "😍", number: 2, assetName: "heart eyes", isLooping: false),
        EmojiType(unicode: "😂", number: 3, assetName: "laughter", isLooping: false),
        EmojiType(unicode: "😮", number: 4, assetName: "oh", isLooping: false)
    ]
    
    private var spaceId: String?
    private let emissionDuration: TimeInterval = 5.0
    private let cooldownDuration: TimeInterval = 5.0
    
    // App model reference for user info
    private let appModel = AppModel.shared
    
    // Emoji type definition
    struct EmojiType: Identifiable {
        let id = UUID()
        let unicode: String
        let number: Int
        let assetName: String
        let isLooping: Bool
    }
    
    func setSpaceId(_ spaceId: String) {
        self.spaceId = spaceId
    }
    
    func processEmojiTap(emoji: String) {
        guard !isOnCooldown, let spaceId = spaceId else { return }
        
        // Get the emoji type
        guard let emojiType = emojiTypes.first(where: { $0.unicode == emoji }) else {
            print("Unknown emoji type: \(emoji)")
            return
        }
        
        // Get user info from AppModel
        let user = appModel.currentUser
        guard !user.id.isEmpty, !user.name.isEmpty else {
            print("❌ Cannot send emoji. User ID or Username is missing from AppModel.")
            return
        }
        
        // Set states for emission period
        isOnCooldown = true // Disables all buttons
        isEmitting = true
        activeEmoji = emoji
        
        // Update visual emitter and send to Firebase
        Task.detached(priority: .userInitiated) {
            await SpacesEntityWrapper.shared.updateVolumetricEmojiTexture(with: emojiType.assetName, isLooping: emojiType.isLooping)
            await SpacesChatManager.shared.sendEmoji(
                emoji: emojiType.number,
                spaceId: spaceId,
                senderId: user.id,
                senderName: user.name
            )
        }
        
        // Schedule the end of the emission and the start of the cooldown UI
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Wait for the emission to complete
            try? await Task.sleep(for: .seconds(self.emissionDuration))
            
            // End emission state
            self.isEmitting = false
            self.activeEmoji = nil
            
            // Wait for the cooldown to complete
            try? await Task.sleep(for: .seconds(self.cooldownDuration))
            
            // End cooldown state
            self.isOnCooldown = false
        }
    }
    
    deinit {
        // No tasks to cancel as they are short-lived
    }
}
