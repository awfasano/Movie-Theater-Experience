import XCTest
@testable import Movie_Theater_Experience

@MainActor
final class SpacesChatViewModelTests: XCTestCase {
    
    func testSendMessageTrimsWhitespaceAndDelegates() {
        let mockManager = MockSpacesChatManager()
        mockManager.expectation = expectation(description: "sendMessage called")
        let user = SharePlayUser(id: "user-1", name: "Tester")
        
        let viewModel = SpacesChatViewModel(
            spaceId: "space-123",
            spacesManager: mockManager,
            currentUserProvider: { user },
            autoStartListening: false
        )
        
        viewModel.sendMessage(text: "   Hello Spaces   ")
        
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(mockManager.lastSend?.text, "Hello Spaces")
        XCTAssertEqual(mockManager.lastSend?.spaceId, "space-123")
    }
    
    func testSendMessageDoesNotSendWhenEmpty() {
        let mockManager = MockSpacesChatManager()
        mockManager.expectation = expectation(description: "should not call")
        mockManager.expectation?.isInverted = true
        
        let viewModel = SpacesChatViewModel(
            spaceId: "space-123",
            spacesManager: mockManager,
            currentUserProvider: { SharePlayUser(id: "user", name: "Tester") },
            autoStartListening: false
        )
        
        viewModel.sendMessage(text: "   ")
        waitForExpectations(timeout: 0.5)
    }
    
    func testSendMessageDoesNotSendWhenUserMissing() {
        let mockManager = MockSpacesChatManager()
        mockManager.expectation = expectation(description: "should not call")
        mockManager.expectation?.isInverted = true
        
        let viewModel = SpacesChatViewModel(
            spaceId: "space-123",
            spacesManager: mockManager,
            currentUserProvider: { SharePlayUser(id: "", name: "") },
            autoStartListening: false
        )
        
        viewModel.sendMessage(text: "Hello")
        waitForExpectations(timeout: 0.5)
    }
    
    func testCleanupStopsListening() {
        let mockManager = MockSpacesChatManager()
        let stopExpectation = expectation(description: "stopListening called")
        mockManager.stopExpectation = stopExpectation
        
        let viewModel = SpacesChatViewModel(
            spaceId: "space-123",
            spacesManager: mockManager,
            currentUserProvider: { SharePlayUser(id: "user", name: "Tester") },
            autoStartListening: false
        )
        
        viewModel.cleanup()
        wait(for: [stopExpectation], timeout: 1.0)
    }
}

private final class MockSpacesChatManager: SpacesChatManaging {
    struct SendCall {
        let text: String
        let senderId: String
        let senderName: String
        let spaceId: String
    }
    
    var lastSend: SendCall?
    var expectation: XCTestExpectation?
    var stopExpectation: XCTestExpectation?
    
    @MainActor func startListening(spaceId: String) {}
    
    @MainActor func stopListening() {
        stopExpectation?.fulfill()
    }
    
    @MainActor func getMessages() -> [ChatMessage] { [] }
    
    @MainActor func getMessageOpacity(for id: String) -> Double { 1.0 }
    
    @MainActor func updateMessageOpacity(id: String, opacity: Double) {}
    
    func sendMessage(_ text: String, senderId: String, senderName: String, spaceId: String) async {
        lastSend = SendCall(text: text, senderId: senderId, senderName: senderName, spaceId: spaceId)
        expectation?.fulfill()
    }
}
