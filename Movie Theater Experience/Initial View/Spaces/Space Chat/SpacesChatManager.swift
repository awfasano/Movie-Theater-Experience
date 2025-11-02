//
//  SpacesChatManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 7/8/25.
//

import Foundation
import FirebaseFirestore
import Combine

/// A service for handling chat and emoji functionality specifically for Spaces
@Observable
class SpacesChatManager: ObservableObject {
    // MARK: - Properties
    
    static let shared = SpacesChatManager()
    
    @MainActor private(set) var messages: [ChatMessage] = []
    @MainActor private(set) var messageOpacities: [String: Double] = [:]
    private var listenerStartTime: Date?
    private let emojiAgeThreshold: TimeInterval = 45.0
    
    private var db = Firestore.firestore(database: "uploads")
    private var listener: ListenerRegistration?
    
    // Batch update properties
    private var pendingChanges: [(DocumentChange, isProcessed: Bool)] = []
    private var batchUpdateTimer: Timer?
    private let batchUpdateInterval: TimeInterval = 0.1
    
    // Performance optimization
    private let messageQueue = DispatchQueue(label: "com.app.spaceschat", qos: .userInteractive)
    private var isProcessingBatch = false
    
    private init() {}
    
    // MARK: - Listener Management
    
    @MainActor
    func startListening(spaceId: String) {
        guard listener == nil else {
            print("Spaces chat listener already active")
            return
        }
        
        listenerStartTime = Date()
        print("📝 Spaces chat listener started at: \(listenerStartTime?.description ?? "unknown")")
        
        let messagesPath = "Spaces/\(spaceId)/messages"
        
        // Use includeMetadataChanges: false to reduce updates
        listener = db.collection(messagesPath)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snapshot, error in
                print("DEBUG: Firebase listener received an update.") // NEW LOG
                guard let self = self else { return }
                
                if let error = error {
                    print("Error fetching spaces chat data: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                // Batch document changes
                self.messageQueue.async {
                    self.pendingChanges.append(contentsOf: snapshot.documentChanges.map { ($0, false) })
                    self.scheduleBatchUpdate()
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
        batchUpdateTimer?.invalidate()
        batchUpdateTimer = nil
        pendingChanges.removeAll()
        print("Spaces chat listener stopped and cleaned up")
    }
    
    // MARK: - Batch Processing
    
    private func scheduleBatchUpdate() {
        guard batchUpdateTimer == nil && !isProcessingBatch else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.batchUpdateTimer = Timer.scheduledTimer(withTimeInterval: self?.batchUpdateInterval ?? 0.1, repeats: false) { _ in
                self?.processBatchUpdate()
            }
        }
    }
    
    private func processBatchUpdate() {
        guard !isProcessingBatch else { return }
        
        isProcessingBatch = true
        batchUpdateTimer = nil
        
        messageQueue.async { [weak self] in
            guard let self = self else { return }
            
            let changesToProcess = self.pendingChanges.filter { !$0.isProcessed }
            guard !changesToProcess.isEmpty else {
                self.isProcessingBatch = false
                return
            }
            
            // Mark as processed
            for i in 0..<self.pendingChanges.count {
                self.pendingChanges[i].isProcessed = true
            }
            
            // Process on main thread
            Task { @MainActor in
                // Begin updates
                var hasChanges = false
                
                for (change, _) in changesToProcess {
                    if self.processDocumentChange(change) {
                        hasChanges = true
                    }
                }
                
                // Clean up processed changes
                self.messageQueue.async {
                    self.pendingChanges.removeAll { $0.isProcessed }
                    self.isProcessingBatch = false
                }
                
                // Notify observers only if there were actual changes
                if hasChanges {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    // MARK: - Document Change Handling
    
    @MainActor
    private func processDocumentChange(_ change: DocumentChange) -> Bool {
        let doc = change.document
        guard let timestamp = doc.get("timestamp") as? Timestamp,
              let messageType = doc.get("type") as? Bool else {
            print("Invalid spaces chat document format")
            return false
        }
        
        if messageType {
            return handleMessage(doc, timestamp: timestamp, changeType: change.type)
        } else {
            handleEmoji(doc, timestamp: timestamp, changeType: change.type)
            return false // Emojis don't affect the message list
        }
    }
    
    @MainActor
    private func handleMessage(_ doc: QueryDocumentSnapshot, timestamp: Timestamp, changeType: DocumentChangeType) -> Bool {
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
                return true
            }
        case .modified:
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
                return true
            }
        case .removed:
            // Check if message exists before removing
            if messages.contains(where: { $0.id == message.id }) {
                messages.removeAll(where: { $0.id == message.id })
                messageOpacities.removeValue(forKey: message.id)
                return true
            }
        }
        
        return false
    }
    
    @MainActor
    private func handleEmoji(_ doc: QueryDocumentSnapshot, timestamp: Timestamp, changeType: DocumentChangeType) {
        print("STEP 1: Remote emoji event received from Firebase.") // LOGGING
        guard changeType == .added else {
            print("📝 Skipping non-added emoji event in spaces: \(changeType)")
            return
        }
        
        guard let emojiNumber = doc.get("emoji") as? Int,
              let senderId = doc.get("senderId") as? String else {
            print("❌ Missing required emoji data in spaces")
            return
        }
        
        guard let listenerStart = listenerStartTime else {
            print("⚠️ No spaces listener start time recorded")
            return
        }
        
        let emojiDate = timestamp.dateValue()
        let ageOfEmoji = listenerStart.timeIntervalSince(emojiDate)
        
        guard ageOfEmoji <= emojiAgeThreshold else {
            print("⏭️ Skipping old emoji from spaces: \(emojiDate)")
            return
        }
        
        let appModel = AppModel.current
        print("DEBUG: Incoming senderId: \(senderId), Local userId: \(appModel.currentUser.id)") // DETAILED LOGGING
        guard senderId != appModel.currentUser.id else {
            print("Skipping own emoji event")
            return
        }
        
        let emojiImageName = emojiToImageName(emojiNumber)
        print("STEP 2: Triggering emitter with image '\(emojiImageName)' and isLooping: false.") // LOGGING
        print("🚀 Processing space emoji: \(emojiImageName)")
        
        // Update visual emitter asynchronously
        Task.detached(priority: .userInitiated) {
            await SpacesEntityWrapper.shared.updateVolumetricEmojiTexture(with: emojiImageName, isLooping: false)
        }
    }
    
    // MARK: - Message Operations
    
    func sendMessage(_ text: String, senderId: String, senderName: String, spaceId: String) async {
        let messageData: [String: Any] = [
            "content": text,
            "timestamp": Timestamp(date: Date()),
            "senderId": senderId,
            "senderName": senderName,
            "type": true
        ]
        
        await sendToFirebase(data: messageData, spaceId: spaceId)
    }
    
    // MARK: - Emoji Operations
    
    func sendEmoji(emoji: Int, spaceId: String, senderId: String, senderName: String) async {
        let emojiData: [String: Any] = [
            "timestamp": Timestamp(date: Date()),
            "senderId": senderId,
            "senderName": senderName,
            "emoji": emoji,
            "type": false
        ]
        
        await sendToFirebase(data: emojiData, spaceId: spaceId)
    }
    
    // MARK: - Firebase Interaction
    
    private func sendToFirebase(data: [String: Any], spaceId: String) async {
        do {
            try await db.collection("Spaces")
                .document(spaceId)
                .collection("messages")
                .addDocument(data: data)
        } catch {
            print("Error sending to Firebase for spaces: \(error)")
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
