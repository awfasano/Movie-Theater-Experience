//
//  SpacesEmojiViewModel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/10/25.
//

import Foundation
import SwiftUI

class SpacesEmojiViewModel: ObservableObject {
    @Published var isOnCooldown = false
    @Published var emojiTypes: [EmojiType] = []
    
    private var spaceId: String?
    private let cooldownDuration: TimeInterval = 2.0
    
    // User information
    @AppStorage("username") private var currentUsername: String = "User"
    @AppStorage("userId") private var currentUserId: String = ""
    
    // Emoji type definition
    struct EmojiType {
        let unicode: String
        let number: Int
        let assetName: String
    }
    
    init() {
        setupEmojiTypes()
    }
    
    func setSpaceId(_ spaceId: String) {
        self.spaceId = spaceId
    }
    
    private func setupEmojiTypes() {
        emojiTypes = [
            EmojiType(unicode: "❤️", number: 0, assetName: "heart"),
            EmojiType(unicode: "😢", number: 1, assetName: "crying"),
            EmojiType(unicode: "😍", number: 2, assetName: "heart eyes"),
            EmojiType(unicode: "😂", number: 3, assetName: "laughter"),
            EmojiType(unicode: "😮", number: 4, assetName: "oh")
        ]
    }
    
    @MainActor
    func processEmojiTap(emoji: String) async {
        guard !isOnCooldown, let spaceId = spaceId else { return }
        
        // Get the emoji type
        guard let emojiType = emojiTypes.first(where: { $0.unicode == emoji }) else {
            print("Unknown emoji type: \(emoji)")
            return
        }
        
        // Start cooldown
        isOnCooldown = true
        
        // Get user ID
        var userId = currentUserId
        if userId.isEmpty {
            userId = UUID().uuidString
            currentUserId = userId
        }
        
        // Update visual emitter
        SpacesEntityWrapper.shared.updateVolumetricEmojiTexture(with: emojiType.assetName)
        
        // Send to Firebase
        SpacesChatManager.shared.sendEmoji(
            emoji: emojiType.number,
            spaceId: spaceId,
            senderId: userId,
            senderName: currentUsername
        )
        
        // Wait for cooldown
        try? await Task.sleep(for: .seconds(cooldownDuration))
        
        // End cooldown
        isOnCooldown = false
    }
}
