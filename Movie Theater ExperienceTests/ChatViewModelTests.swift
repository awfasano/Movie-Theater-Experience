
import XCTest
@testable import Movie_Theater_Experience

@MainActor
class ChatViewModelTests: XCTestCase {

    var viewModel: ChatViewModel!
    var mockEventManager: MockEventManager!

    override func setUp() {
        super.setUp()
        mockEventManager = MockEventManager()
        viewModel = ChatViewModel(eventId: "testEvent", date: Date(), eventManager: mockEventManager)
    }

    override func tearDown() {
        viewModel = nil
        mockEventManager = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertEqual(viewModel.eventId, "testEvent")
        XCTAssertNotNil(viewModel.date)
    }

    func testSendMessage() {
        let initialMessageCount = mockEventManager.messages.count
        viewModel.sendMessage(text: "Hello, World!")
        XCTAssertEqual(mockEventManager.messages.count, initialMessageCount + 1)
        XCTAssertEqual(mockEventManager.messages.last?.content, "Hello, World!")
    }

    func testUpdateMessages() async {
        let message = ChatMessage(id: "123", timestamp: Date(), content: "Test message", senderId: "sender1", senderName: "Sender")
        mockEventManager.addMessage(message)
        
        await viewModel.updateMessages()
        
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.content, "Test message")
    }

    func testGetOpacity() async {
        let messageId = "opacityTest"
        await mockEventManager.updateMessageOpacity(id: messageId, opacity: 0.5)
        
        let opacity = await viewModel.getOpacity(for: messageId)
        
        XCTAssertEqual(opacity, 0.5)
    }

    func testUpdateMessageOpacity() async {
        let messageId = "opacityUpdateTest"
        
        await viewModel.updateMessageOpacity(id: messageId, opacity: 0.7)
        
        let updatedOpacity = await mockEventManager.getMessageOpacity(for: messageId)
        XCTAssertEqual(updatedOpacity, 0.7)
    }
}

class MockEventManager: EventManagerProtocol {
    @MainActor var messages: [ChatMessage] = []
    private var messageOpacities: [String: Double] = [:]

    func startListening(eventId: String, date: Date) { }

    func stopListening() { }

    @MainActor func sendMessage(_ content: String, senderId: String, senderName: String, eventId: String, date: Date) {
        let message = ChatMessage(id: UUID().uuidString, timestamp: Date(), content: content, senderId: senderId, senderName: senderName)
        messages.append(message)
    }

    @MainActor func addMessage(_ message: ChatMessage) {
        messages.append(message)
    }

    func getMessageOpacity(for id: String) async -> Double {
        return messageOpacities[id, default: 1.0]
    }

    func updateMessageOpacity(id: String, opacity: Double) async {
        messageOpacities[id] = opacity
    }
}
