import FirebaseFirestore
import Combine
import SwiftUI

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    private let sharedListener = SharedFirebaseListener.shared
    private var cancellables = Set<AnyCancellable>()
    
    let eventId: String
    let dateString: String
    
    init(eventId: String, date: Date) {
        self.eventId = eventId
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        self.dateString = formatter.string(from: date)
        
        // Start the shared listener
        sharedListener.startListener(eventId: eventId, dateString: dateString)
        
        // Set up message binding with proper memory management
        sharedListener.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMessages in
                self?.messages = newMessages
            }
            .store(in: &cancellables)
    }
    
    func getOpacity(id: String) -> Double {
        return sharedListener.getOpacity(id: id)
    }
    
    func updateMessageOpacity(id: String, opacity: Double) {
        sharedListener.updateMessageOpacity(id: id, opacity: opacity)
    }
    
    func sendMessage(text: String) {
        guard !text.isEmpty else { return }
        
        let newMessageData = [
            "content": text,
            "timestamp": Timestamp(date: Date()),
            "senderId": "currentUserId",
            "senderName": "Anthony",
            "type": true
        ] as [String: Any]
        
        // Use standard Firestore instance
        let db = Firestore.firestore(database: "movieexperiencedb")
        db.collection("Public Rooms")
            .document(dateString)
            .collection("Events")
            .document(eventId)
            .collection("messages")
            .addDocument(data: newMessageData) { error in
                if let error = error {
                    print("Error sending message: \(error)")
                }
            }
    }
    
    deinit {
        // Clean up subscriptions
        cancellables.removeAll()
    }
}
