import SwiftUI
import Firebase
import FirebaseFirestore
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    private let eventManager = FirebaseEventManager.shared
    
    let eventId: String
    let date: Date
    
    // Retrieve the current user's name from user settings.
    @AppStorage("username") private var currentUsername: String = "User"
    // Persist the userId using AppStorage. This will be our single source of truth.
    @AppStorage("userId") private var currentUserId: String = ""
    
    init(eventId: String, date: Date) {
        self.eventId = eventId
        self.date = date
        
        Task {
            await startListening()
        }
    }
    
    private func startListening() async {
        // Start the Firebase event manager listener.
        await eventManager.startListening(eventId: eventId, date: date)
        
        // Initialize messages and observe changes.
        await updateMessages()
        
        // Start continuous updates.
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                await updateMessages()
            }
        }
    }
    
    private func updateMessages() async {
        let currentMessages = await eventManager.messages
        if self.messages != currentMessages {
            self.messages = currentMessages
        }
    }
    
    func getOpacity(for id: String) async -> Double {
        return await eventManager.getMessageOpacity(for: id)
    }
    
    func updateMessageOpacity(id: String, opacity: Double) async {
        await eventManager.updateMessageOpacity(id: id, opacity: opacity)
    }
    
    func sendMessage(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Use the stored userId from AppStorage. If it's empty, generate a new one.
        var senderId = currentUserId
        if senderId.isEmpty {
            senderId = UUID().uuidString
            currentUserId = senderId
            print("Generated new userId: \(senderId)")
        } else {
            print("Using existing userId: \(senderId)")
        }
        
        let senderName = currentUsername
        print("ChatViewModel.sendMessage -> senderId: \(senderId), senderName: \(senderName)")
        
        // Pass the message along with senderId and senderName to the event manager.
        eventManager.sendMessage(trimmedText,
                                 senderId: senderId,
                                 senderName: senderName,
                                 eventId: eventId,
                                 date: date)
    }
}
