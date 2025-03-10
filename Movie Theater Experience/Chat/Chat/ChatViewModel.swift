import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    private let eventManager = FirebaseEventManager.shared
    
    let eventId: String
    let date: Date
    
    init(eventId: String, date: Date) {
        self.eventId = eventId
        self.date = date
        
        Task {
            await startListening()
        }
    }
    
    private func startListening() async {
        // Start the Firebase event manager listener
        await eventManager.startListening(eventId: eventId, date: date)
        
        // Initialize messages and observe changes
        await updateMessages()
        
        // Start continuous updates
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
        guard !text.isEmpty else { return }
        eventManager.sendMessage(text, eventId: eventId, date: date)
    }
}
