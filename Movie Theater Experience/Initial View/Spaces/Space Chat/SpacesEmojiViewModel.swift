
//
//  SpacesEmojiViewModel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/10/25.
//

import Foundation
import SwiftUI

protocol EmojiTextureUpdating {
    func updateTexture(name: String, isLooping: Bool) async
}

protocol SpacesEmojiSending {
    func sendEmoji(number: Int, spaceId: String, senderId: String, senderName: String) async
}

protocol EmojiSleepClock {
    func sleep(seconds: TimeInterval) async
}

struct SpacesEmojiEmitter: EmojiTextureUpdating {
    func updateTexture(name: String, isLooping: Bool) async {
        SpacesEntityWrapper.shared.updateVolumetricEmojiTexture(with: name, isLooping: isLooping)
    }
}

struct TaskEmojiSleepClock: EmojiSleepClock {
    func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

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
    private let emissionDuration: TimeInterval
    private let cooldownDuration: TimeInterval
    private let emojiEmitter: EmojiTextureUpdating
    private let emojiSender: SpacesEmojiSending
    private let sleepClock: EmojiSleepClock
    private let currentUserProvider: @MainActor () -> SharePlayUser
    
    // Emoji type definition
    struct EmojiType: Identifiable {
        let id = UUID()
        let unicode: String
        let number: Int
        let assetName: String
        let isLooping: Bool
    }
    
    init(
        emissionDuration: TimeInterval = 5.0,
        cooldownDuration: TimeInterval = 5.0,
        emojiEmitter: EmojiTextureUpdating = SpacesEmojiEmitter(),
        emojiSender: SpacesEmojiSending = SpacesChatManager.shared,
        sleepClock: EmojiSleepClock = TaskEmojiSleepClock(),
        currentUserProvider: @escaping @MainActor () -> SharePlayUser = { AppModel.current.currentUser }
    ) {
        self.emissionDuration = emissionDuration
        self.cooldownDuration = cooldownDuration
        self.emojiEmitter = emojiEmitter
        self.emojiSender = emojiSender
        self.sleepClock = sleepClock
        self.currentUserProvider = currentUserProvider
    }
    
    func setSpaceId(_ spaceId: String) {
        self.spaceId = spaceId
    }
    
    func processEmojiTap(emoji: String) {
        guard !isOnCooldown, let spaceId = spaceId else { return }
        
        guard let emojiType = emojiTypes.first(where: { $0.unicode == emoji }) else {
            print("Unknown emoji type: \(emoji)")
            return
        }
        
        let user = currentUserProvider()
        guard !user.id.isEmpty, !user.name.isEmpty else {
            print("❌ Cannot send emoji. User ID or Username is missing from AppModel.")
            return
        }
        
        isOnCooldown = true
        isEmitting = true
        activeEmoji = emoji
        
        Task {
            await emojiEmitter.updateTexture(name: emojiType.assetName, isLooping: emojiType.isLooping)
            await emojiSender.sendEmoji(
                number: emojiType.number,
                spaceId: spaceId,
                senderId: user.id,
                senderName: user.name
            )
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            await self.sleepClock.sleep(seconds: self.emissionDuration)
            self.isEmitting = false
            self.activeEmoji = nil
            await self.sleepClock.sleep(seconds: self.cooldownDuration)
            self.isOnCooldown = false
        }
    }
    
    deinit {
        // No tasks to cancel as they are short-lived
    }
}

extension SpacesChatManager: SpacesEmojiSending {
    func sendEmoji(number: Int, spaceId: String, senderId: String, senderName: String) async {
        await sendEmoji(emoji: number, spaceId: spaceId, senderId: senderId, senderName: senderName)
    }
}
