//
//  HostedEvents.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
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

    private let db = Firestore.firestore(database: "uploads")
    private var personaManager: PersonaTableManager?
    
    private var participantsListener: ListenerRegistration?
    private var tablesListener: ListenerRegistration?
    private var gameStateListener: ListenerRegistration?
    
    // Dependency injection for PersonaTableManager
    func setPersonaManager(_ manager: PersonaTableManager) {
        self.personaManager = manager
    }
    
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
            return .success(existing)
        }

        let participant = EventParticipant(userId: currentUserId, userName: currentUserName, role: .participant)
        
        do {
            try await participantDoc.setData(from: participant)
            participants.append(participant)
            currentEvent = event
            startListeners(for: eventId)
            return .success(participant)
        } catch {
            print("Firestore join error: \(error)")
            return .failure(.joinFailed)
        }
    }
    
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
                print("Firestore old table update error: \(error)")
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

        if userId == AppModel.shared.currentUserId {
            await (personaManager as? PersonaTableUpdatable)?.updatePersonaForUser(participants[participantIndex], tables: tables)
        }

        do {
            try await participantDoc.setData(from: participants[participantIndex])
            try await tableDoc.setData(from: table)
            return .success(())
        } catch {
            print("Firestore assign error: \(error)")
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
    
    private func startListeners(for eventId: String) {
        participantsListener?.remove()
        tablesListener?.remove()
        gameStateListener?.remove()
        
        participantsListener = db.collection("Events").document(eventId).collection("participants").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            guard let docs = snapshot?.documents else { return }
            let updated = docs.compactMap { try? $0.data(as: EventParticipant.self) }
            DispatchQueue.main.async { self.participants = updated }
        }
        
        tablesListener = db.collection("Events").document(eventId).collection("tables").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            guard let docs = snapshot?.documents else { return }
            let updated = docs.compactMap { try? $0.data(as: EventTable.self) }
            DispatchQueue.main.async { self.tables = updated }
        }
        
        gameStateListener = db.collection("Events").document(eventId).collection("gameState").document("current").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else { return }
            if let state = try? Firestore.Decoder().decode(GameState.self, from: data) {
                DispatchQueue.main.async { self.gameState = state }
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
    
    func startGame() async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else { return .failure(.eventNotFound) }
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
            return .success(())
        } catch {
            print("Firestore start game error: \(error)")
            return .failure(.unknown)
        }
    }
    
    func awardPoints(to tableNumber: Int, points: Int) async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else { return .failure(.eventNotFound) }
        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else { return .failure(.unknown) }
        state.scores["\(tableNumber)", default: 0] += points
        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            return .success(())
        } catch {
            print("Firestore award points error: \(error)")
            return .failure(.unknown)
        }
    }

    // MARK: - New methods for round/question progression and notifications
    
    func nextRound() async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else { return .failure(.eventNotFound) }
        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else { return .failure(.unknown) }
        state.currentRound += 1
        state.currentQuestion = 1
        state.status = .waiting
        state.trigger = nil
        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            return .success(())
        } catch {
            print("Firestore next round error: \(error)")
            return .failure(.unknown)
        }
    }
    
    func nextQuestion() async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else { return .failure(.eventNotFound) }
        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else { return .failure(.unknown) }
        state.currentQuestion = (state.currentQuestion ?? 0) + 1
        state.status = .question_active
        state.trigger = nil
        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            return .success(())
        } catch {
            print("Firestore next question error: \(error)")
            return .failure(.unknown)
        }
    }
    
    var notificationActions: [String] {
        return ["Show Instructions", "Announce Round", "Reveal Answer"]
    }
    
    func triggerNotification(_ name: String) async {
        guard let event = currentEvent, let eventId = event.id else { return }
        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else { return }
        state.trigger = name
        try? await dbEventRef.collection("gameState").document("current").setData(from: state)
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
            
            // Generate and save game statistics
            await saveGameStatistics(eventId: eventId)
            
            // Notify all participants
            await notifyGameEnd()
            
            return .success(())
        } catch {
            return .failure(.unknown)
        }
    }
    
    private func saveGameStatistics(eventId: String) async {
        // Calculate MVP, participation rates, average scores, etc.
        let stats = GameStatistics(
            eventId: eventId,
            endTime: Date(),
            totalParticipants: participants.count,
            winningTable: getWinningTable(),
            averageScore: calculateAverageScore(),
            questionsAnswered: getQuestionsAnsweredCount()
        )
        
        // Save to Firebase for historical tracking
        // TODO: Implement saving of stats
    }
    
    // MARK: - Helpers used by statistics and notifications
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
        // If currentQuestion represents the number asked so far, use that, else 0
        return gameState?.currentQuestion ?? 0
    }

    private func notifyGameEnd() async {
        // TODO: Implement real notification fanout. For now, no-op placeholder.
    }
}

protocol PersonaTableUpdatable {
    func updatePersonaForUser(_ participant: EventParticipant, tables: [EventTable]) async
}

enum HostedEventError: Error {
    case eventNotFound
    case joinFailed
    case tableAssignmentFailed
    case insufficientPermissions
    case unknown
}

// Assuming GameState model updated as:

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

