
import Foundation

protocol EventManagerProtocol {
    var messages: [ChatMessage] { get }
    func startListening(eventId: String, date: Date)
    func stopListening()
    func sendMessage(_ content: String, senderId: String, senderName: String, eventId: String, date: Date)
    func getMessageOpacity(for id: String) async -> Double
    func updateMessageOpacity(id: String, opacity: Double) async
}
