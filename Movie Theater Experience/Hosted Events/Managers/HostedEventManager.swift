//
//  Enhanced HostedEventManager.swift
//  Movie Theater Experience
//
//  Integrates SharePlay for real-time host notifications and game sync
//

import Foundation
import FirebaseFirestore
import Combine
import SwiftUI

@MainActor
class HostedEventManager: ObservableObject {
    static let shared = HostedEventManager()
    
    @Published private(set) var currentEvent: CalendarEvent?
    @Published private(set) var participants: [EventParticipant] = []
    @Published private(set) var tables: [EventTable] = []
    @Published private(set) var gameState: GameState?
    @Published private(set) var isHost: Bool = false
    
    // SharePlay integration
    @Published var sharePlayActive: Bool = false
    @Published var liveNotifications: [HostNotification] = []

    private let db = Firestore.firestore(database: "uploads")
    private var personaManager: PersonaTableManager?
    
    private var participantsListener: ListenerRegistration?
    private var tablesListener: ListenerRegistration?
    private var gameStateListener: ListenerRegistration?
    private var sharePlayCancellables = Set<AnyCancellable>()
    
    private init() {
        setupSharePlayListeners()
    }
    
    // MARK: - SharePlay Integration
    
    private func setupSharePlayListeners() {
        // Listen for SharePlay session status
        TriviaSharePlayManager.shared.$isSessionActive
            .receive(on: DispatchQueue.main)
            .assign(to: \.sharePlayActive, on: self)
            .store(in: &sharePlayCancellables)
        
        // Listen for host notifications
        NotificationCenter.default.publisher(for: .sharePlayHostNotification)
            .compactMap { $0.object as? HostNotification }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleSharePlayNotification(notification)
            }
            .store(in: &sharePlayCancellables)
        
        // Listen for question start events
        NotificationCenter.default.publisher(for: .sharePlayQuestionStart)
            .compactMap { $0.object as? QuestionStartMessage }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] questionStart in
                self?.handleSharePlayQuestionStart(questionStart)
            }
            .store(in: &sharePlayCancellables)
    }
    
    private func handleSharePlayNotification(_ notification: HostNotification) {
        print("📢 [HostedEvent] Received SharePlay notification: \(notification.message)")
        
        // Add to live notifications for immediate display
        liveNotifications.append(notification)
        
        // Remove after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.liveNotifications.removeAll { $0.message == notification.message }
        }
        
        // Update game state if it's a trigger
        if var state = gameState {
            state.trigger = notification.message
            gameState = state
        }
    }
    
    private func handleSharePlayQuestionStart(_ questionStart: QuestionStartMessage) {
        print("❓ [HostedEvent] SharePlay question started: \(questionStart.questionId)")
        
        // Sync local timer if needed
        // This ensures all devices start timers at exactly the same time
    }
    
    // MARK: - SharePlay Activity Management
    
    func startSharePlaySession() async -> Bool {
        guard let event = currentEvent, let eventId = event.id else {
            print("❌ [HostedEvent] Cannot start SharePlay - no current event")
            return false
        }
        
        let activity = TriviaEventActivity(
            eventId: eventId,
            eventTitle: event.title,
            spaceId: event.id ?? ""
        )
        
        await TriviaSharePlayManager.shared.startSession(for: activity)
        return TriviaSharePlayManager.shared.isSessionActive
    }
    
    func endSharePlaySession() {
        TriviaSharePlayManager.shared.endSession()
    }
    
    // Dependency injection for PersonaTableManager
    func setPersonaManager(_ manager: PersonaTableManager) {
        self.personaManager = manager
    }
    
    // MARK: - Enhanced Event Management
    
    func joinHostedEvent(_ event: CalendarEvent) async -> Result<EventParticipant, HostedEventError> {
        let currentUserIdRaw = AppModel.shared.currentUserId
        let currentUserId = currentUserIdRaw.isEmpty ? "currentUserIdPlaceholder" : currentUserIdRaw
        let currentUserNameRaw = AppModel.shared.username
        let currentUserName = currentUserNameRaw.isEmpty ? "Current User" : currentUserNameRaw
        
        guard let eventId = event.id else {
            return .failure(.eventNotFound)
        }
        
        let participantDoc = db.collection("Events").document(eventId).collection("participants").document(currentUserId)

        if let existing = participants.first(where: { $0.userId == currentUserId }) {
            currentEvent = event
            startListeners(for: eventId)
            
            // Auto-start SharePlay if not already active
            if !sharePlayActive {
                Task {
                    _ = await startSharePlaySession()
                }
            }
            
            return .success(existing)
        }

        let participant = EventParticipant(userId: currentUserId, userName: currentUserName, role: .participant)
        
        do {
            try await participantDoc.setData(from: participant)
            participants.append(participant)
            currentEvent = event
            startListeners(for: eventId)
            
            // Auto-start SharePlay for new participants
            Task {
                _ = await startSharePlaySession()
            }
            
            return .success(participant)
        } catch {
            print("❌ [HostedEvent] Firestore join error: \(error)")
            return .failure(.joinFailed)
        }
    }
    
    // MARK: - Enhanced Host Controls with SharePlay
    
    func triggerNotification(_ name: String) async {
        guard let event = currentEvent, let eventId = event.id else {
            print("⚠️ [HostedEvent] No current event for notification")
            return
        }
        
        print("📢 [HostedEvent] Triggering notification: \(name)")
        
        // 1. Immediate SharePlay notification for real-time feedback
        if sharePlayActive {
            await TriviaSharePlayManager.shared.sendHostNotification(
                name,
                type: "instruction",
                eventId: eventId
            )
        }
        
        // 2. Update Firebase for persistence
        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else {
            print("⚠️ [HostedEvent] No game state for notification")
            return
        }
        
        state.trigger = name
        
        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            gameState = state
            print("✅ [HostedEvent] Notification saved to Firebase")
        } catch {
            print("❌ [HostedEvent] Failed to save notification: \(error)")
        }
    }
    
    // MARK: - Table Assignment with SharePlay
    
    func assignUserToTable(_ userId: String, tableNumber: Int) async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }
        
        let dbEventRef = db.collection("Events").document(eventId)
        let participantDoc = dbEventRef.collection("participants").document(userId)
        let tableDoc = dbEventRef.collection("tables").document("\(tableNumber)")

        guard let participantIndex = participants.firstIndex(where: { $0.userId == userId }) else {
            return .failure(.eventNotFound)
        }
        guard let tableIndex = tables.firstIndex(where: { $0.tableNumber == tableNumber }) else {
            return .failure(.tableAssignmentFailed)
        }
        
        var table = tables[tableIndex]
        if table.isFull {
            return .failure(.tableAssignmentFailed)
        }

        // Remove participant from old table if assigned
        if let oldTableNumber = participants[participantIndex].tableNumber,
           let oldTableIndex = tables.firstIndex(where: { $0.tableNumber == oldTableNumber }) {
            var oldTable = tables[oldTableIndex]
            oldTable.participants.removeAll(where: { $0 == userId })
            tables[oldTableIndex] = oldTable
            do {
                try await dbEventRef.collection("tables").document("\(oldTableNumber)").setData(from: oldTable)
            } catch {
                print("❌ [HostedEvent] Old table update error: \(error)")
            }
        }

        guard let seatIndex = firstAvailableSeatIndex(for: table) else {
            return .failure(.tableAssignmentFailed)
        }

        // Update participant info
        participants[participantIndex].tableNumber = tableNumber
        participants[participantIndex].seatIndex = seatIndex

        if !table.participants.contains(userId) {
            table.participants.append(userId)
        }

        tables[tableIndex] = table

        // Update persona position if it's the current user
        if userId == AppModel.shared.currentUserId {
            await (personaManager as? PersonaTableUpdatable)?.updatePersonaForUser(participants[participantIndex], tables: tables)
        }

        do {
            try await participantDoc.setData(from: participants[participantIndex])
            try await tableDoc.setData(from: table)
            
            print("✅ [HostedEvent] User \(userId) assigned to table \(tableNumber)")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Table assignment error: \(error)")
            return .failure(.tableAssignmentFailed)
        }
    }
    
    func moveParticipant(_ userId: String, to tableNumber: Int) async -> Result<Void, HostedEventError> {
        return await assignUserToTable(userId, tableNumber: tableNumber)
    }
    
    private func firstAvailableSeatIndex(for table: EventTable) -> Int? {
        let maxSeats = table.maxSeats
        let takenSeats = Set(table.participants.compactMap { userId in
            participants.first(where: { $0.userId == userId })?.seatIndex
        })
        for index in 0..<maxSeats {
            if !takenSeats.contains(index) {
                return index
            }
        }
        return nil
    }
    
    // MARK: - Game Management with SharePlay
    
    func startGame() async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }
        
        let dbEventRef = db.collection("Events").document(eventId)
        let initialGameState = GameState(
            currentRound: 1,
            status: .waiting,
            scores: [:],
            currentQuestion: 0,
            trigger: nil
        )
        
        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: initialGameState)
            gameState = initialGameState
            
            // Notify via SharePlay
            if sharePlayActive {
                await TriviaSharePlayManager.shared.sendHostNotification(
                    "Game Started! Get ready for Round 1",
                    type: "announcement",
                    eventId: eventId
                )
            }
            
            print("✅ [HostedEvent] Game started")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Start game error: \(error)")
            return .failure(.unknown)
        }
    }
    
    func nextRound() async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }
        
        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else {
            return .failure(.unknown)
        }
        
        state.currentRound += 1
        state.currentQuestion = 1
        state.status = .waiting
        state.trigger = nil
        
        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            gameState = state
            
            // Notify via SharePlay
            if sharePlayActive {
                await TriviaSharePlayManager.shared.sendHostNotification(
                    "Round \(state.currentRound) Starting!",
                    type: "announcement",
                    eventId: eventId
                )
            }
            
            print("✅ [HostedEvent] Advanced to round \(state.currentRound)")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Next round error: \(error)")
            return .failure(.unknown)
        }
    }
    
    func nextQuestion() async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }
        
        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else {
            return .failure(.unknown)
        }
        
        state.currentQuestion = (state.currentQuestion ?? 0) + 1
        state.status = .question_active
        state.trigger = nil
        
        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            gameState = state
            
            // Notify via SharePlay with question sync
            if sharePlayActive {
                await TriviaSharePlayManager.shared.sendHostNotification(
                    "Question \(state.currentQuestion) is now active",
                    type: "instruction",
                    eventId: eventId
                )
            }
            
            print("✅ [HostedEvent] Advanced to question \(state.currentQuestion)")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Next question error: \(error)")
            return .failure(.unknown)
        }
    }
    
    func awardPoints(to tableNumber: Int, points: Int) async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }
        
        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else {
            return .failure(.unknown)
        }
        
        let oldScore = state.scores["\(tableNumber)", default: 0]
        state.scores["\(tableNumber)", default: 0] += points
        let newScore = state.scores["\(tableNumber)"]!
        
        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            gameState = state
            
            // Notify via SharePlay
            if sharePlayActive {
                let tableName = tables.first(where: { $0.tableNumber == tableNumber })?.teamName ?? "Table \(tableNumber)"
                await TriviaSharePlayManager.shared.sendHostNotification(
                    "\(tableName) awarded \(points) points! New score: \(newScore)",
                    type: "scoring",
                    eventId: eventId
                )
            }
            
            print("✅ [HostedEvent] Awarded \(points) points to table \(tableNumber)")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Award points error: \(error)")
            return .failure(.unknown)
        }
    }
    
    func endGame() async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }
        
        // Update game state to finished
        var finalState = gameState ?? GameState(
            currentRound: 0,
            status: .finished,
            scores: [:],
            currentQuestion: nil,
            trigger: nil
        )
        finalState.status = .finished
        
        // Save final state
        do {
            try await db.collection("Events")
                .document(eventId)
                .collection("gameState")
                .document("current")
                .setData(from: finalState)
            
            gameState = finalState
            
            // Generate and save game statistics
            await saveGameStatistics(eventId: eventId)
            
            // Notify all participants via SharePlay
            if sharePlayActive {
                let winningTable = getWinningTable()
                let winnerName = winningTable.flatMap { tableNum in
                    tables.first(where: { $0.tableNumber == tableNum })?.teamName ?? "Table \(tableNum)"
                } ?? "No winner"
                
                await TriviaSharePlayManager.shared.sendHostNotification(
                    "Game Over! Winner: \(winnerName)",
                    type: "celebration",
                    eventId: eventId
                )
            }
            
            print("✅ [HostedEvent] Game ended successfully")
            return .success(())
        } catch {
            print("❌ [HostedEvent] End game error: \(error)")
            return .failure(.unknown)
        }
    }
    
    // MARK: - Firebase Listeners
    
    private func startListeners(for eventId: String) {
        stopListeners()
        
        participantsListener = db.collection("Events").document(eventId).collection("participants").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            guard let docs = snapshot?.documents else {
                if let error = error {
                    print("❌ [HostedEvent] Participants listener error: \(error)")
                }
                return
            }
            let updated = docs.compactMap { try? $0.data(as: EventParticipant.self) }
            DispatchQueue.main.async {
                self.participants = updated
                print("👥 [HostedEvent] Updated participants: \(updated.count)")
            }
        }
        
        tablesListener = db.collection("Events").document(eventId).collection("tables").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            guard let docs = snapshot?.documents else {
                if let error = error {
                    print("❌ [HostedEvent] Tables listener error: \(error)")
                }
                return
            }
            let updated = docs.compactMap { try? $0.data(as: EventTable.self) }
            DispatchQueue.main.async {
                self.tables = updated
                print("🪑 [HostedEvent] Updated tables: \(updated.count)")
            }
        }
        
        gameStateListener = db.collection("Events").document(eventId).collection("gameState").document("current").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else {
                if let error = error {
                    print("❌ [HostedEvent] Game state listener error: \(error)")
                }
                return
            }
            if let state = try? Firestore.Decoder().decode(GameState.self, from: data) {
                DispatchQueue.main.async {
                    self.gameState = state
                    print("🎮 [HostedEvent] Updated game state: Round \(state.currentRound)")
                }
            }
        }
    }
    
    private func stopListeners() {
        participantsListener?.remove()
        tablesListener?.remove()
        gameStateListener?.remove()
        participantsListener = nil
        tablesListener = nil
        gameStateListener = nil
    }
    
    // MARK: - Statistics and Cleanup
    
    private func saveGameStatistics(eventId: String) async {
        let stats = GameStatistics(
            eventId: eventId,
            endTime: Date(),
            totalParticipants: participants.count,
            winningTable: getWinningTable(),
            averageScore: calculateAverageScore(),
            questionsAnswered: getQuestionsAnsweredCount()
        )
        
        // Save to Firebase for historical tracking
        do {
            try await db.collection("GameStatistics").document(eventId).setData(from: stats)
            print("✅ [HostedEvent] Game statistics saved")
        } catch {
            print("❌ [HostedEvent] Failed to save statistics: \(error)")
        }
    }
    
    private func getWinningTable() -> Int? {
        guard let state = gameState else { return nil }
        return state.scores.max(by: { $0.value < $1.value }).flatMap { Int($0.key) }
    }

    private func calculateAverageScore() -> Double {
        guard let state = gameState, !state.scores.isEmpty else { return 0 }
        let total = state.scores.values.reduce(0, +)
        return Double(total) / Double(state.scores.count)
    }

    private func getQuestionsAnsweredCount() -> Int {
        return gameState?.currentQuestion ?? 0
    }
    
    // MARK: - Computed Properties
    
    var notificationActions: [String] {
        return [
            "Show Instructions",
            "Announce Round",
            "Reveal Answer",
            "Time Warning",
            "Final Answers",
            "Round Complete"
        ]
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Use Task to call MainActor methods from deinit
        Task { @MainActor in
            stopListeners()
        }
        sharePlayCancellables.removeAll()
    }
}

// MARK: - Supporting Protocols

protocol PersonaTableUpdatable {
    func updatePersonaForUser(_ participant: EventParticipant, tables: [EventTable]) async
}

// MARK: - Error Types

enum HostedEventError: Error {
    case eventNotFound
    case joinFailed
    case tableAssignmentFailed
    case insufficientPermissions
    case unknown
}

// MARK: - Data Models

struct GameState: Codable {
    var currentRound: Int
    var status: GameStatus
    var scores: [String: Int]
    var currentQuestion: Int?
    var trigger: String?
}

enum GameStatus: String, Codable {
    case waiting
    case question_active
    case finished
}

struct GameStatistics: Codable {
    var eventId: String
    var endTime: Date
    var totalParticipants: Int
    var winningTable: Int?
    var averageScore: Double
    var questionsAnswered: Int
}
