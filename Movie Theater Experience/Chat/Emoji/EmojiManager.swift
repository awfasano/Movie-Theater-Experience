import Foundation
import FirebaseFirestore

/// Configuration struct for building the Firestore path.
/// For example, for movie experience you might use "Public Rooms",
/// and for spaces you might use "Spaces".
struct EmojiManagerConfiguration {
    let rootCollection: String
    
    func collectionReference(db: Firestore, eventId: String, date: Date) -> CollectionReference {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        let dateString = formatter.string(from: date)
        return db.collection(rootCollection)
            .document(dateString)
            .collection("Events")
            .document(eventId)
            .collection("messages")
    }
}


@Observable
final class EmojiManager: ObservableObject {
    static let shared = EmojiManager()
    
    private let db: Firestore
    private let theatreWrapper = TheatreEntityWrapper.shared
    
    private let appModel = AppModel.shared
    
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
    
    var configuration: EmojiManagerConfiguration
    
    private init(db: Firestore = Firestore.firestore(database: "movieexperiencedb"),
                 configuration: EmojiManagerConfiguration = EmojiManagerConfiguration(rootCollection: "Public Rooms")) {
        self.db = db
        self.configuration = configuration
    }
    
    /// Processes an emoji tap.
    /// - Parameters:
    ///   - emoji: The tapped emoji as a String.
    ///   - eventId: The event (or space) identifier.
    ///   - date: The current date.
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
        
        // Update visual emitter via the theatre wrapper.
        theatreWrapper.updateVolumetricEmojiTexture(with: emojiType.assetName)
        
        // Send the emoji data to Firebase.
        await sendToFirebase(emojiNumber: emojiType.number, eventId: eventId, date: date)
        
        // Wait for cooldown duration.
        try? await Task.sleep(for: .seconds(cooldownDuration))
        
        // End cooldown
        isOnCooldown = false
    }
    
    /// Sends the emoji data to Firebase using the configured Firestore path.
    private func sendToFirebase(emojiNumber: Int, eventId: String, date: Date) async {
        let emojiData: [String: Any] = await [
            "timestamp": Timestamp(date: Date()),
            "senderId": appModel.currentUserId,
            "senderName": appModel.username,
            "emoji": emojiNumber,
            "seatOrTheatre": false,
            "type": false
        ]
        
        // Build the collection reference from the configuration.
        let collectionRef = configuration.collectionReference(db: db, eventId: eventId, date: date)
        
        do {
            try await collectionRef.addDocument(data: emojiData)
            print("✅ Emoji sent successfully to Firebase")
        } catch {
            print("❌ Error sending emoji: \(error)")
        }
    }
}
