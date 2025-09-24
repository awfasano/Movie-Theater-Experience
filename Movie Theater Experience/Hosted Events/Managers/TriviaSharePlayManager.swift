//
//  TriviaSharePlayMessages.swift
//  Movie Theater Experience
//
//  SharePlay message types for trivia system
//

import Foundation

// MARK: - SharePlay Message Types

enum TriviaSharePlayMessage: Codable {
    case questionStart(QuestionStartMessage)
    case vote(VoteMessage)
    case hostNotification(HostNotification)
    case tableConsensus(TableConsensusMessage)
    case emojiReaction(EmojiReactionMessage)
    case timerSync(TimerSyncMessage)
}

struct QuestionStartMessage: Codable {
    let questionId: String
    let startTime: Date
    let timeLimit: Int
    let eventId: String
}

struct VoteMessage: Codable {
    let userId: String
    let userName: String
    let tableNumber: Int
    let answer: Int
    let timestamp: Date
}

struct HostNotification: Codable {
    let message: String
    let type: String // "instruction", "announcement", etc.
    let timestamp: Date
    let eventId: String
}

struct TableConsensusMessage: Codable {
    let tableNumber: Int
    let finalAnswer: Int
    let submittedBy: String
    let timestamp: Date
}

struct EmojiReactionMessage: Codable {
    let userId: String
    let tableNumber: Int
    let emoji: String
    let timestamp: Date
}

struct TimerSyncMessage: Codable {
    let timeRemaining: Int
    let isActive: Bool
    let timestamp: Date
}

//
//  Enhanced TriviaSharePlayManager.swift
//  Movie Theater Experience
//
//  Updated to handle trivia-specific messages
//

import Foundation
import GroupActivities
import Combine

@MainActor
class TriviaSharePlayManager: ObservableObject {
    static let shared = TriviaSharePlayManager()
    
    @Published var isSessionActive = false
    @Published var participants: Set<Participant> = []
    @Published var localParticipantID: Participant.ID?
    
    private var groupSession: GroupSession<TriviaEventActivity>?
    private var messenger: GroupSessionMessenger?
    private var subscriptions = Set<AnyCancellable>()
    
    // MARK: - Message Handlers
    private var messageHandlers: [String: (TriviaSharePlayMessage) async -> Void] = [:]
    
    private init() {
        setupMessageHandlers()
    }
    
    // MARK: - Session Management
    
    func startSession(for activity: TriviaEventActivity) async {
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            do {
                _ = try await activity.activate()
                print("✅ [SharePlay] Trivia activity activated successfully")
            } catch {
                print("❌ [SharePlay] Failed to activate trivia activity: \(error)")
            }
        case .activationDisabled:
            print("⚠️ [SharePlay] SharePlay is disabled")
        default:
            print("ℹ️ [SharePlay] Activation cancelled or unknown")
        }
    }
    
    func configureGroupSession(_ session: GroupSession<TriviaEventActivity>) {
        print("🔧 [SharePlay] Configuring group session...")
        
        // Clean up existing session
        groupSession?.leave()
        subscriptions.removeAll()
        
        self.groupSession = session
        self.isSessionActive = true
        
        // Set up messenger for sending/receiving messages
        self.messenger = GroupSessionMessenger(session: session)
        
        // Track participants
        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                if let participantSet = participants as? Set<Participant> {
                    self?.participants = participantSet
                    print("👥 [SharePlay] Updated participants: \(participantSet.count)")
                }
            }
            .store(in: &subscriptions)
        
        // Listen for incoming messages
        Task {
            for await (message, _) in messenger!.messages(of: TriviaSharePlayMessage.self) {
                await handleIncomingMessage(message)
            }
        }
        
        // Join the session
        session.join()
        print("✅ [SharePlay] Joined trivia session")
    }
    
    // MARK: - Message Sending
    
    func sendQuestionStart(_ questionId: String, timeLimit: Int, eventId: String) async {
        let message = TriviaSharePlayMessage.questionStart(
            QuestionStartMessage(
                questionId: questionId,
                startTime: Date(),
                timeLimit: timeLimit,
                eventId: eventId
            )
        )
        await sendMessage(message)
    }
    
    func sendVote(userId: String, userName: String, tableNumber: Int, answer: Int) async {
        let message = TriviaSharePlayMessage.vote(
            VoteMessage(
                userId: userId,
                userName: userName,
                tableNumber: tableNumber,
                answer: answer,
                timestamp: Date()
            )
        )
        await sendMessage(message)
    }
    
    func sendHostNotification(_ text: String, type: String, eventId: String) async {
        let message = TriviaSharePlayMessage.hostNotification(
            HostNotification(
                message: text,
                type: type,
                timestamp: Date(),
                eventId: eventId
            )
        )
        await sendMessage(message)
    }
    
    func sendTableConsensus(tableNumber: Int, finalAnswer: Int, submittedBy: String) async {
        let message = TriviaSharePlayMessage.tableConsensus(
            TableConsensusMessage(
                tableNumber: tableNumber,
                finalAnswer: finalAnswer,
                submittedBy: submittedBy,
                timestamp: Date()
            )
        )
        await sendMessage(message)
    }
    
    func sendEmojiReaction(userId: String, tableNumber: Int, emoji: String) async {
        let message = TriviaSharePlayMessage.emojiReaction(
            EmojiReactionMessage(
                userId: userId,
                tableNumber: tableNumber,
                emoji: emoji,
                timestamp: Date()
            )
        )
        await sendMessage(message)
    }
    
    func sendTimerSync(timeRemaining: Int, isActive: Bool) async {
        let message = TriviaSharePlayMessage.timerSync(
            TimerSyncMessage(
                timeRemaining: timeRemaining,
                isActive: isActive,
                timestamp: Date()
            )
        )
        await sendMessage(message)
    }
    
    func sendMessage(_ message: TriviaSharePlayMessage) async {
        guard let messenger = messenger else {
            print("⚠️ [SharePlay] No messenger available")
            return
        }
        
        do {
            try await messenger.send(message)
            print("📤 [SharePlay] Sent message: \(message)")
        } catch {
            print("❌ [SharePlay] Failed to send message: \(error)")
        }
    }
    
    // MARK: - Message Handling Setup
    
    private func setupMessageHandlers() {
        // Register handlers for different message types
        registerMessageHandler("vote") { message in
            if case .vote(let voteMessage) = message {
                await self.handleVoteMessage(voteMessage)
            }
        }
        
        registerMessageHandler("hostNotification") { message in
            if case .hostNotification(let notification) = message {
                await self.handleHostNotification(notification)
            }
        }
        
        registerMessageHandler("questionStart") { message in
            if case .questionStart(let questionStart) = message {
                await self.handleQuestionStart(questionStart)
            }
        }
        
        registerMessageHandler("tableConsensus") { message in
            if case .tableConsensus(let consensus) = message {
                await self.handleTableConsensus(consensus)
            }
        }
        
        registerMessageHandler("emojiReaction") { message in
            if case .emojiReaction(let emoji) = message {
                await self.handleEmojiReaction(emoji)
            }
        }
        
        registerMessageHandler("timerSync") { message in
            if case .timerSync(let timer) = message {
                await self.handleTimerSync(timer)
            }
        }
    }
    
    func registerMessageHandler(_ type: String, handler: @escaping (TriviaSharePlayMessage) async -> Void) {
        messageHandlers[type] = handler
    }
    
    private func handleIncomingMessage(_ message: TriviaSharePlayMessage) async {
        print("📥 [SharePlay] Received message: \(message)")
        
        // Route to appropriate handler
        switch message {
        case .vote:
            await messageHandlers["vote"]?(message)
        case .hostNotification:
            await messageHandlers["hostNotification"]?(message)
        case .questionStart:
            await messageHandlers["questionStart"]?(message)
        case .tableConsensus:
            await messageHandlers["tableConsensus"]?(message)
        case .emojiReaction:
            await messageHandlers["emojiReaction"]?(message)
        case .timerSync:
            await messageHandlers["timerSync"]?(message)
        }
    }
    
    // MARK: - Message Handlers
    
    private func handleVoteMessage(_ vote: VoteMessage) async {
        print("🗳️ [SharePlay] Vote received: \(vote.userName) voted \(vote.answer) at table \(vote.tableNumber)")
        
        // Notify the appropriate table collaboration manager
        NotificationCenter.default.post(
            name: .sharePlayVoteReceived,
            object: vote
        )
    }
    
    private func handleHostNotification(_ notification: HostNotification) async {
        print("📢 [SharePlay] Host notification: \(notification.message)")
        
        // Show immediate UI feedback
        NotificationCenter.default.post(
            name: .sharePlayHostNotification,
            object: notification
        )
    }
    
    private func handleQuestionStart(_ questionStart: QuestionStartMessage) async {
        print("❓ [SharePlay] Question started: \(questionStart.questionId)")
        
        // Sync timer start across all devices
        NotificationCenter.default.post(
            name: .sharePlayQuestionStart,
            object: questionStart
        )
    }
    
    private func handleTableConsensus(_ consensus: TableConsensusMessage) async {
        print("✅ [SharePlay] Table consensus: Table \(consensus.tableNumber) submitted answer \(consensus.finalAnswer)")
        
        // Show visual feedback for table submission
        NotificationCenter.default.post(
            name: .sharePlayTableConsensus,
            object: consensus
        )
    }
    
    private func handleEmojiReaction(_ emoji: EmojiReactionMessage) async {
        print("😀 [SharePlay] Emoji reaction: \(emoji.emoji) from table \(emoji.tableNumber)")
        
        // Trigger visual emoji effect
        SpacesEntityWrapper.shared.updateVolumetricEmojiTexture(with: emoji.emoji, isLooping: false)
    }
    
    private func handleTimerSync(_ timer: TimerSyncMessage) async {
        print("⏰ [SharePlay] Timer sync: \(timer.timeRemaining)s remaining")
        
        // Sync timer across devices
        NotificationCenter.default.post(
            name: .sharePlayTimerSync,
            object: timer
        )
    }
    
    // MARK: - Session Cleanup
    
    func endSession() {
        print("🔚 [SharePlay] Ending trivia session")
        
        groupSession?.end()
        groupSession = nil
        messenger = nil
        isSessionActive = false
        participants.removeAll()
        localParticipantID = nil
        subscriptions.removeAll()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sharePlayVoteReceived = Notification.Name("sharePlayVoteReceived")
    static let sharePlayHostNotification = Notification.Name("sharePlayHostNotification")
    static let sharePlayQuestionStart = Notification.Name("sharePlayQuestionStart")
    static let sharePlayTableConsensus = Notification.Name("sharePlayTableConsensus")
    static let sharePlayTimerSync = Notification.Name("sharePlayTimerSync")
}
