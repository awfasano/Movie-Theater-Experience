import Foundation
import FirebaseFirestore
import Combine
import SwiftUI

class SharedFirebaseListener: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var messageOpacities: [String: Double] = [:]
    
    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    static let shared = SharedFirebaseListener()
    
    private init() {}
    
    func startListener(eventId: String, dateString: String) {
        // Only start a new listener if we don't already have one
        guard listener == nil else {
            print("Listener already active, skipping initialization")
            return
        }
        
        print("Starting Firebase listener for event: \(eventId), date: \(dateString)")
        
        listener = db.collection("Public Rooms")
            .document(dateString)
            .collection("Events")
            .document(eventId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching chat: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                for change in snapshot.documentChanges {
                    guard let type = change.document.get("type") as? Bool,
                          let timestamp = change.document.get("timestamp") as? Timestamp else {
                        continue
                    }
                    
                    if type {
                        self?.handleChatMessage(change.document, timestamp: timestamp, changeType: change.type)
                    } else {
                        self?.handleEmitter(change.document, timestamp: timestamp)
                    }
                }
            }
    }
    
    private func handleChatMessage(_ doc: QueryDocumentSnapshot, timestamp: Timestamp, changeType: DocumentChangeType) {
        let chatMessage = ChatMessage(
            id: doc.documentID,
            timestamp: timestamp.dateValue(),
            content: doc.get("content") as? String ?? "",
            senderId: doc.get("senderId") as? String ?? "",
            senderName: doc.get("senderName") as? String ?? ""
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch changeType {
            case .added:
                if !self.messages.contains(where: { $0.id == chatMessage.id }) {
                    self.messages.append(chatMessage)
                    self.messageOpacities[chatMessage.id] = 1.0
                }
            case .modified:
                if let index = self.messages.firstIndex(where: { $0.id == chatMessage.id }) {
                    self.messages[index] = chatMessage
                }
            case .removed:
                self.messages.removeAll(where: { $0.id == chatMessage.id })
                self.messageOpacities.removeValue(forKey: chatMessage.id)
            }
        }
    }
    
    private func handleEmitter(_ doc: QueryDocumentSnapshot, timestamp: Timestamp) {
        guard let emoji = doc.get("emoji") as? Int,
              let seatOrTheatre = doc.get("seatOrTheatre") as? Bool,
              !seatOrTheatre else { // Only process theatre emojis
            return
        }
        
        let emojiImageName = self.getEmojiImageName(emoji)
        DispatchQueue.main.async {
            TheatreEntityWrapper.shared.updateVolumetricEmojiTexture(with: emojiImageName)
        }
    }
    
    private func getEmojiImageName(_ emoji: Int) -> String {
        switch emoji {
        case 0: return "heart"
        case 1: return "crying"
        case 2: return "heart eyes"
        case 3: return "laughter"
        case 4: return "oh"
        default: return "heart"
        }
    }
    
    func updateMessageOpacity(id: String, opacity: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.messageOpacities[id] = opacity
            self?.objectWillChange.send()
        }
    }
    
    func getOpacity(id: String) -> Double {
        return messageOpacities[id] ?? 1.0
    }
    
    func stopListener() {
        listener?.remove()
        listener = nil
        print("Firebase listener stopped")
    }
    
    deinit {
        stopListener()
    }
}
