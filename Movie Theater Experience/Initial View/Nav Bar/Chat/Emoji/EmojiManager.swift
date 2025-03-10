//
//  EmitterService.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 11/19/24.
//

import Foundation
import FirebaseFirestore


@Observable
class EmojiManager {
    static let shared = EmojiManager()
    private let db = Firestore.firestore(database: "movieexperiencedb")
    private let theatreWrapper = TheatreEntityWrapper.shared
    
    @MainActor var isOnCooldown = false
    private let cooldownDuration: TimeInterval = 2.0
    
    struct EmojiType {
        let unicode: String
        let number: Int
        let assetName: String
    }
    
    let emojiTypes: [EmojiType] = [
        EmojiType(unicode: "❤️", number: 0, assetName: "heart"),
        EmojiType(unicode: "😢", number: 1, assetName: "crying"),
        EmojiType(unicode: "😍", number: 2, assetName: "heart eyes"),
        EmojiType(unicode: "😂", number: 3, assetName: "laughter"),
        EmojiType(unicode: "😮", number: 4, assetName: "oh")
    ]
    
    private init() {}
    
    @MainActor
    func processEmojiTap(emoji: String, eventId: String, date: Date) async {
        guard !isOnCooldown else {
            print("⏳ Emoji on cooldown")
            return
        }
        
        guard let emojiType = emojiTypes.first(where: { $0.unicode == emoji }) else {
            print("❌ Invalid emoji type")
            return
        }
        
        // Start cooldown
        isOnCooldown = true
        
        // Update visual emitter
        theatreWrapper.updateVolumetricEmojiTexture(with: emojiType.assetName)
        
        // Send to Firebase
        await sendToFirebase(
            emojiNumber: emojiType.number,
            eventId: eventId,
            date: date
        )
        
        // Wait for cooldown
        try? await Task.sleep(for: .seconds(cooldownDuration))
        
        // End cooldown
        isOnCooldown = false
    }
    
    private func sendToFirebase(emojiNumber: Int, eventId: String, date: Date) async {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        let dateString = formatter.string(from: date)
        
        let emojiData: [String: Any] = [
            "timestamp": Timestamp(date: Date()),
            "senderId": "currentUserId",
            "senderName": "Anthony",
            "emoji": emojiNumber,
            "seatOrTheatre": false,
            "type": false
        ]
        
        do {
            try await db.collection("Public Rooms")
                .document(dateString)
                .collection("Events")
                .document(eventId)
                .collection("messages")
                .addDocument(data: emojiData)
            
            print("✅ Emoji sent successfully to Firebase")
        } catch {
            print("❌ Error sending emoji: \(error)")
        }
    }
}
