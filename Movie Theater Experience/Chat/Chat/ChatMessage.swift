import Firebase
import FirebaseFirestore
import Combine


struct ChatMessage: Identifiable, Equatable, Hashable {
    let id: String
    let timestamp: Date
    let content: String
    let senderId: String
    let senderName: String
    
    // Removed opacityCalc and yPosition as they're now handled by the ViewModel
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Removed Codable conformance since we're not serializing directly
}
