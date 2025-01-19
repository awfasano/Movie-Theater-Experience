//
//  FirebaseEventManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/9/25.
//

import Foundation
import FirebaseFirestore
import Combine

@Observable
class FirebaseEventManager {
    static let shared = FirebaseEventManager()
    private var messages: [ChatMessage] = []
    private var messageOpacities: [String: Double] = [:]
    
    private var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    private init() {}
    
    func startListening(eventId: String, date: Date) {
        guard listener == nil else {
            print("Event listener already active")
            return
        }
        
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
                
                snapshot.documentChanges.forEach { change in
                    self?.handleDocumentChange(change)
                }
            }
    }
    
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
    
    private func handleEmoji(_ doc: QueryDocumentSnapshot, timestamp: Timestamp, changeType: DocumentChangeType) {
        guard case .added = changeType else { return }
        
        let emoji = Emitters(
            id: doc.documentID,
            timestamp: timestamp.dateValue(),
            senderId: doc.get("senderId") as? String ?? "",
            senderName: doc.get("senderName") as? String ?? "",
            emoji: doc.get("emoji") as? Int ?? 0,
            seatOrTheatre: doc.get("seatOrTheatre") as? Bool ?? true
        )
        
        if !emoji.seatOrTheatre {
            let emojiImageName = emojiToImageName(emoji.emoji)
            DispatchQueue.main.async {
                TheatreEntityWrapper.shared.updateVolumetricEmojiTexture(with: emojiImageName)
            }
        }
    }
    
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
    
    func sendMessage(_ text: String, eventId: String, date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        let dateString = formatter.string(from: date)
        
        let messageData: [String: Any] = [
            "content": text,
            "timestamp": Timestamp(date: Date()),
            "senderId": "currentUserId",
            "senderName": "Anthony",
            "type": true
        ]
        
        db.collection("Public Rooms")
            .document(dateString)
            .collection("Events")
            .document(eventId)
            .collection("messages")
            .addDocument(data: messageData)
    }
    
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
            "type": false
        ]
        
        db.collection("Public Rooms")
            .document(dateString)
            .collection("Events")
            .document(eventId)
            .collection("messages")
            .addDocument(data: emojiData)
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        messages.removeAll()
        messageOpacities.removeAll()
        print("Event listener stopped and cleaned up")
    }
    
    func getMessages() -> [ChatMessage] {
        return messages
    }
    
    func getMessageOpacity(for id: String) -> Double {
        return messageOpacities[id] ?? 1.0
    }
    
    func updateMessageOpacity(id: String, opacity: Double) {
        messageOpacities[id] = opacity
    }
}
