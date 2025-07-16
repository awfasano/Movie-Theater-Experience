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
    @Published var cooldownProgress: Double = 0.0
    @Published var activeEmoji: String? = nil
    
    // Static emoji types to avoid recreation
    let emojiTypes: [EmojiType] = [
        EmojiType(unicode: "❤️", number: 0, assetName: "heart"),
        EmojiType(unicode: "😢", number: 1, assetName: "crying"),
        EmojiType(unicode: "😍", number: 2, assetName: "heart eyes"),
        EmojiType(unicode: "😂", number: 3, assetName: "laughter"),
        EmojiType(unicode: "😮", number: 4, assetName: "oh")
    ]
    
    private var spaceId: String?
    private let cooldownDuration: TimeInterval = 2.0
    var cooldownTask: Task<Void, Never>?
    
    // App model reference for user info
    private let appModel = AppModel.shared
    
    // Emoji type definition
    struct EmojiType: Identifiable {
        let id = UUID()
        let unicode: String
        let number: Int
        let assetName: String
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
        
        // Set active emoji for animation
        activeEmoji = emoji
        
        // Start cooldown immediately
        isOnCooldown = true
        cooldownProgress = 1.0
        
        // Update visual emitter on a background queue to prevent blocking
        Task.detached(priority: .userInitiated) { [weak self] in
            await SpacesEntityWrapper.shared.updateVolumetricEmojiTexture(with: emojiType.assetName)
            
            // Send to Firebase
            await SpacesChatManager.shared.sendEmoji(
                emoji: emojiType.number,
                spaceId: spaceId,
                senderId: user.id,
                senderName: user.name
            )
        }
        
        // Animate cooldown
        startCooldownAnimation()
    }
    
    func startCooldownAnimation() {
        // Cancel any existing cooldown
        cooldownTask?.cancel()
        
        cooldownTask = Task { [weak self] in
            guard let self = self else { return }
            
            let steps = 20
            let stepDuration = self.cooldownDuration / Double(steps)
            
            for i in 0..<steps {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    self.cooldownProgress = Double(steps - i - 1) / Double(steps)
                }
                
                try? await Task.sleep(for: .seconds(stepDuration))
            }
            
            if !Task.isCancelled {
                await MainActor.run {
                    self.isOnCooldown = false
                    self.cooldownProgress = 0.0
                    self.activeEmoji = nil
                }
            }
        }
    }
    
    deinit {
        cooldownTask?.cancel()
    }
}
