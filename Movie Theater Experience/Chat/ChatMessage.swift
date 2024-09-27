import Firebase
import FirebaseFirestore
import Combine


struct ChatMessage:Identifiable,Equatable, Hashable,Encodable, Decodable {
    let id: String
    let timestamp: Date
    let content: String
    var opacityCalc:Double = 1
    let senderId: String
    let senderName: String // Added property
    var yPosition: CGFloat? = 0// Add this line
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id // Assuming message IDs are unique
    }
}

