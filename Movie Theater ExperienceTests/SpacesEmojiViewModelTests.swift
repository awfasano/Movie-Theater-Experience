import XCTest
@testable import Movie_Theater_Experience

@MainActor
final class SpacesEmojiViewModelTests: XCTestCase {
    
    func testProcessEmojiTapTriggersEmitterAndSender() async {
        let emitter = MockEmojiEmitter()
        let sender = MockEmojiSender()
        let clock = MockEmojiClock()
        let viewModel = SpacesEmojiViewModel(
            emissionDuration: 1,
            cooldownDuration: 1,
            emojiEmitter: emitter,
            emojiSender: sender,
            sleepClock: clock,
            currentUserProvider: { SharePlayUser(id: "user", name: "Tester") }
        )
        viewModel.setSpaceId("space-123")
        
        viewModel.processEmojiTap(emoji: "❤️")
        await Task.yield()
        
        XCTAssertTrue(viewModel.isOnCooldown)
        XCTAssertTrue(viewModel.isEmitting)
        XCTAssertEqual(emitter.updatedTextures.count, 1)
        XCTAssertEqual(sender.sentEmojis.count, 1)
        
        clock.resumeNextSleep()
        await Task.yield()
        XCTAssertFalse(viewModel.isEmitting)
        XCTAssertNotNil(viewModel.activeEmoji)
        
        clock.resumeNextSleep()
        await Task.yield()
        XCTAssertFalse(viewModel.isOnCooldown)
        XCTAssertNil(viewModel.activeEmoji)
    }
    
    func testProcessEmojiTapIgnoredDuringCooldown() async {
        let emitter = MockEmojiEmitter()
        let sender = MockEmojiSender()
        let viewModel = SpacesEmojiViewModel(
            emissionDuration: 1,
            cooldownDuration: 1,
            emojiEmitter: emitter,
            emojiSender: sender,
            sleepClock: MockEmojiClock(),
            currentUserProvider: { SharePlayUser(id: "user", name: "Tester") }
        )
        viewModel.setSpaceId("space-123")
        
        viewModel.processEmojiTap(emoji: "❤️")
        await Task.yield()
        XCTAssertTrue(viewModel.isOnCooldown)
        
        viewModel.processEmojiTap(emoji: "😢")
        await Task.yield()
        XCTAssertEqual(emitter.updatedTextures.count, 1)
        XCTAssertEqual(sender.sentEmojis.count, 1)
    }
    
    func testProcessEmojiTapNoSpaceIdDoesNothing() async {
        let emitter = MockEmojiEmitter()
        let sender = MockEmojiSender()
        let viewModel = SpacesEmojiViewModel(
            emissionDuration: 0,
            cooldownDuration: 0,
            emojiEmitter: emitter,
            emojiSender: sender,
            sleepClock: MockEmojiClock(),
            currentUserProvider: { SharePlayUser(id: "user", name: "Tester") }
        )
        
        viewModel.processEmojiTap(emoji: "❤️")
        await Task.yield()
        XCTAssertFalse(viewModel.isOnCooldown)
        XCTAssertTrue(emitter.updatedTextures.isEmpty)
        XCTAssertTrue(sender.sentEmojis.isEmpty)
    }
}

// MARK: - Mocks

final class MockEmojiEmitter: EmojiTextureUpdating {
    struct UpdateCall {
        let name: String
        let isLooping: Bool
    }
    var updatedTextures: [UpdateCall] = []
    func updateTexture(name: String, isLooping: Bool) async {
        updatedTextures.append(UpdateCall(name: name, isLooping: isLooping))
    }
}

final class MockEmojiSender: SpacesEmojiSending {
    struct SendCall {
        let number: Int
        let spaceId: String
        let senderId: String
        let senderName: String
    }
    var sentEmojis: [SendCall] = []
    func sendEmoji(number: Int, spaceId: String, senderId: String, senderName: String) async {
        sentEmojis.append(SendCall(number: number, spaceId: spaceId, senderId: senderId, senderName: senderName))
    }
}

final class MockEmojiClock: EmojiSleepClock {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func sleep(seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
    
    func resumeNextSleep() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}
