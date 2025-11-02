import Foundation

protocol SpacesChatManaging: AnyObject {
    @MainActor func startListening(spaceId: String)
    @MainActor func stopListening()
    @MainActor func getMessages() -> [ChatMessage]
    @MainActor func getMessageOpacity(for id: String) -> Double
    @MainActor func updateMessageOpacity(id: String, opacity: Double)
    func sendMessage(_ text: String, senderId: String, senderName: String, spaceId: String) async
}

extension SpacesChatManager: SpacesChatManaging {}
