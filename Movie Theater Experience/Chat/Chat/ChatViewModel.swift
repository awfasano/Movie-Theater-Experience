import SwiftUI
import Firebase
import FirebaseFirestore
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    
    // Use dependency injection for the event manager.
    private let eventManager: EventManagerProtocol
    
    let eventId: String
    let date: Date
    
    private let appModel = AppModel.current
    
    // MARK: - Initializer
    
    /// Injects an instance of FirebaseEventManager.
    /// You can supply one that's preconfigured for your context.
    init(eventId: String, date: Date, eventManager: EventManagerProtocol = FirebaseEventManager.shared) {
        self.eventId = eventId
        self.date = date
        self.eventManager = eventManager
        
        Task {
            await startListening()
        }
    }
    
    // MARK: - Listener and Message Updates
    
    private func startListening() async {
        // Start the event manager listener.
        eventManager.startListening(eventId: eventId, date: date)
        
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
    
    func updateMessages() async {
        let currentMessages = eventManager.messages
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
    
    // MARK: - Sending Messages
    
    func sendMessage(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // --- GET USER FROM AppModel INSTEAD OF GENERATING A NEW ONE ---
        let senderId = appModel.currentUserId
        let senderName = appModel.username
        
        // This is a critical check
        guard !senderId.isEmpty && !senderName.isEmpty else {
            print("❌ Cannot send message. User ID or Username is missing from AppModel.")
            return
        }

        print("ChatViewModel.sendMessage -> senderId: \(senderId), senderName: \(senderName)")
        
        eventManager.sendMessage(trimmedText,
                                 senderId: senderId,
                                 senderName: senderName,
                                 eventId: eventId,
                                 date: date)
    }
}
