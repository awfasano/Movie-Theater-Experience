import Foundation
import FirebaseFirestore
import Combine

@Observable
final class FirebaseEventManager: ObservableObject, EventManagerProtocol {
    // MARK: - Properties
    
    static let shared = FirebaseEventManager()
    
    @MainActor private(set) var messages: [ChatMessage] = []
    @MainActor private(set) var messageOpacities: [String: Double] = [:]
    private var listenerStartTime: Date?
    private let emojiAgeThreshold: TimeInterval = 45.0
    
    private var db = Firestore.firestore(database: "movieexperiencedb")
    private var listener: ListenerRegistration?
    
    // Default configuration for movie experience.
    var configuration = EventManagerConfiguration(rootCollection: "Public Rooms")
    
    private init() {}
    
    // MARK: - Listener Management
    
    @MainActor
    func startListening(eventId: String, date: Date) {
        guard listener == nil else {
            print("Event listener already active")
            return
        }
        
        // Record the start time when we begin listening
        listenerStartTime = Date()
        print("📝 Listener started at: \(listenerStartTime?.description ?? "unknown")")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        let dateString = formatter.string(from: date)
        
        print("Starting event listener for: \(eventId) on \(dateString)")
        
        listener = db.collection("Public Rooms")
            .document(dateString)
            .collection("Events")
            .document(eventId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching event data: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    snapshot.documentChanges.forEach { change in
                        self?.handleDocumentChange(change)
                    }
                }
            }
    }
    
    @MainActor
    func stopListening() {
        listener?.remove()
        listener = nil
        messages.removeAll()
        messageOpacities.removeAll()
        listenerStartTime = nil
        print("Event listener stopped and cleaned up")
    }
    
    // MARK: - Document Change Handling
    
    @MainActor
    private func handleDocumentChange(_ change: DocumentChange) {
        let doc = change.document
        guard let timestamp = doc.get("timestamp") as? Timestamp,
              let messageType = doc.get("type") as? Bool else {
            print("Invalid document format")
            return
        }
        
        if messageType {
            handleMessage(doc, timestamp: timestamp, changeType: change.type)
        } else {
            handleEmoji(doc, timestamp: timestamp, changeType: change.type)
        }
    }
    
    @MainActor
    private func handleMessage(_ doc: QueryDocumentSnapshot, timestamp: Timestamp, changeType: DocumentChangeType) {
        let message = ChatMessage(
            id: doc.documentID,
            timestamp: timestamp.dateValue(),
            content: doc.get("content") as? String ?? "",
            senderId: doc.get("senderId") as? String ?? "",
            senderName: doc.get("senderName") as? String ?? ""
        )
        
        switch changeType {
        case .added:
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
                messageOpacities[message.id] = 1.0
            }
        case .modified:
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            }
        case .removed:
            messages.removeAll(where: { $0.id == message.id })
            messageOpacities.removeValue(forKey: message.id)
        }
    }
    
    @MainActor
    private func handleEmoji(_ doc: QueryDocumentSnapshot, timestamp: Timestamp, changeType: DocumentChangeType) {
        // Only process added events
        guard changeType == .added else {
            print("📝 Skipping non-added emoji event: \(changeType)")
            return
        }
        
        guard let emojiNumber = doc.get("emoji") as? Int,
              let seatOrTheatre = doc.get("seatOrTheatre") as? Bool,
              let senderId = doc.get("senderId") as? String else {
            print("❌ Missing required emoji data")
            return
        }
        
        // Skip seat emojis
        guard !seatOrTheatre else {
            print("💺 Skipping seat emoji")
            return
        }
        
        // Check if this emoji is too old
        guard let listenerStart = listenerStartTime else {
            print("⚠️ No listener start time recorded")
            return
        }
        
        let emojiDate = timestamp.dateValue()
        let ageOfEmoji = listenerStart.timeIntervalSince(emojiDate)
        
        // Skip if the emoji is older than our threshold
        guard ageOfEmoji <= emojiAgeThreshold else {
            print("⏭️ Skipping old emoji from: \(emojiDate)")
            return
        }
        
        let emojiImageName = emojiToImageName(emojiNumber)
        print("🚀 Processing theatre emoji: \(emojiImageName)")
        
        //TheatreEntityWrapper.shared.updateVolumetricEmojiTexture(with: emojiImageName)
    }
    
    // MARK: - Message Operations
    
    func sendMessage(_ text: String, senderId: String, senderName: String, eventId: String, date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        let dateString = formatter.string(from: date)
        
        let messageData: [String: Any] = [
            "content": text,
            "timestamp": Timestamp(date: Date()),
            "senderId": senderId,
            "senderName": senderName,
            "type": true // true for chat message
        ]
        
        sendToFirebase(data: messageData, eventId: eventId, dateString: dateString)
    }

    
    // MARK: - Emoji Operations
    
    func sendEmoji(emoji: Int, eventId: String, date: Date, seatOrTheatre: Bool) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        let dateString = formatter.string(from: date)
        
        let emojiData: [String: Any] = [
            "timestamp": Timestamp(date: Date()),
            "senderId": "currentUserId",
            "senderName": "Anthony",
            "emoji": emoji,
            "seatOrTheatre": seatOrTheatre,
            "type": false // false for emoji
        ]
        
        sendToFirebase(data: emojiData, eventId: eventId, dateString: dateString)
    }
    
    // MARK: - Firebase Interaction
    
    private func sendToFirebase(data: [String: Any], eventId: String, dateString: String) {
        db.collection("Public Rooms")
            .document(dateString)
            .collection("Events")
            .document(eventId)
            .collection("messages")
            .addDocument(data: data) { error in
                if let error = error {
                    print("Error sending to Firebase: \(error)")
                }
            }
    }
    
    // MARK: - Helper Methods
    
    private func emojiToImageName(_ emojiNumber: Int) -> String {
        switch emojiNumber {
        case 0: return "heart"
        case 1: return "crying"
        case 2: return "heart eyes"
        case 3: return "laughter"
        case 4: return "oh"
        default: return "heart"
        }
    }
    
    @MainActor
    func getMessages() -> [ChatMessage] {
        return messages
    }
    
    @MainActor
    func getMessageOpacity(for id: String) -> Double {
        return messageOpacities[id] ?? 1.0
    }
    
    @MainActor
    func updateMessageOpacity(id: String, opacity: Double) {
        messageOpacities[id] = opacity
    }
}
