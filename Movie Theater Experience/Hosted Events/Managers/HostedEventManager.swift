//
//  HostedEventManager.swift
//  Movie Theater Experience
//
//  Firebase-based trivia event management
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

    private let db = FirebaseEventManager.uploadsDb
    private var personaManager: PersonaTableManager?
    
    private var participantsListener: ListenerRegistration?
    private var tablesListener: ListenerRegistration?
    private var gameStateListener: ListenerRegistration?
    private var eventListener: ListenerRegistration?
    
    private init() {}
    
    // Dependency injection for PersonaTableManager
    func setPersonaManager(_ manager: PersonaTableManager) {
        self.personaManager = manager
    }
    
    // MARK: - Event Management
    
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
            
            // Setup audio rooms when joining as host or first participant
            if participants.isEmpty || isHost {
                Task {
                    await setupAudioRoomsForEvent()
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
            
            // Setup audio rooms when joining as host or first participant
            if participants.isEmpty || isHost {
                Task {
                    await setupAudioRoomsForEvent()
                }
            }
            
            return .success(participant)
        } catch {
            print("❌ [HostedEvent] Firestore join error: \(error)")
            return .failure(.joinFailed)
        }
    }
    
    // MARK: - Host Controls
    
    func updateEventSpace(to spaceId: String) async -> Result<Void, HostedEventError> {
        guard var event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }

        let trimmedId = spaceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            return .failure(.unknown)
        }
        
        do {
            try await db.collection("Events").document(eventId).setData(["spaceId": trimmedId], merge: true)
            event.spaceId = trimmedId
            currentEvent = event
            print("✅ [HostedEvent] Updated event space to '\(trimmedId)'")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Failed to update event space: \(error)")
            return .failure(.unknown)
        }
    }
    
    func triggerNotification(_ name: String) async {
        guard let event = currentEvent, let eventId = event.id else {
            print("⚠️ [HostedEvent] No current event for notification")
            return
        }

        print("📢 [HostedEvent] Triggering notification: \(name)")

        // Send via Firebase
        let messageData: [String: Any] = [
            "message": name,
            "type": "instruction",
            "timestamp": Date(),
            "hostId": AppModel.shared.currentUserId
        ]

        do {
            // Add timeout to prevent indefinite hanging
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.db.collection("Events")
                        .document(eventId)
                        .collection("broadcasts")
                        .addDocument(data: messageData)
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(3))
                    throw HostedEventError.timeout
                }

                // Wait for first to complete
                try await group.next()
                group.cancelAll()
            }

            print("✅ [HostedEvent] Notification sent to Firebase")
        } catch is CancellationError {
            print("✅ [HostedEvent] Notification sent (timeout prevented)")
        } catch {
            print("❌ [HostedEvent] Failed to send notification: \(error)")
        }
    }
    
    // MARK: - Table Assignment
    
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
            
            // Register audio room for this table if it doesn't exist
            Task {
                await registerAudioRoomForTable(table)
            }
            
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
    
    // MARK: - Game Management
    
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

        state.scores["\(tableNumber)", default: 0] += points

        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            gameState = state

            print("✅ [HostedEvent] Awarded \(points) points to table \(tableNumber)")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Award points error: \(error)")
            return .failure(.unknown)
        }
    }

    // MARK: - Answer Submission Management

    func submitAnswer(tableNumber: Int, answer: String? = nil) async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }

        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else {
            return .failure(.unknown)
        }

        // Initialize submissions dict if needed
        if state.submissions == nil {
            state.submissions = [:]
        }

        // Create submission
        let submission = AnswerSubmission(
            tableNumber: tableNumber,
            submittedAt: Date(),
            locked: true,
            answer: answer
        )

        state.submissions?["\(tableNumber)"] = submission

        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            gameState = state

            print("✅ [HostedEvent] Table \(tableNumber) submitted answer")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Submit answer error: \(error)")
            return .failure(.unknown)
        }
    }

    func clearSubmissions() async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }

        let dbEventRef = db.collection("Events").document(eventId)
        guard var state = gameState else {
            return .failure(.unknown)
        }

        state.submissions = [:]

        do {
            try await dbEventRef.collection("gameState").document("current").setData(from: state)
            gameState = state

            print("✅ [HostedEvent] Cleared all submissions")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Clear submissions error: \(error)")
            return .failure(.unknown)
        }
    }

    func getSubmissionStatus(for tableNumber: Int) -> AnswerSubmission? {
        return gameState?.submissions?["\(tableNumber)"]
    }
    
    func endGame() async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }
        
        var finalState = gameState ?? GameState(
            currentRound: 0,
            status: .finished,
            scores: [:],
            currentQuestion: nil,
            trigger: nil
        )
        finalState.status = .finished
        
        do {
            try await db.collection("Events")
                .document(eventId)
                .collection("gameState")
                .document("current")
                .setData(from: finalState)
            
            gameState = finalState
            
            await saveGameStatistics(eventId: eventId)
            await cleanupAudioRooms()
            
            print("✅ [HostedEvent] Game ended successfully")
            return .success(())
        } catch {
            print("❌ [HostedEvent] End game error: \(error)")
            return .failure(.unknown)
        }
    }
    
    // MARK: - FaceTime Link Management

    /// Update the FaceTime link for a specific table
    func updateTableFaceTimeLink(_ tableNumber: Int, faceTimeURL: String) async -> Result<Void, HostedEventError> {
        guard let event = currentEvent, let eventId = event.id else {
            return .failure(.eventNotFound)
        }

        guard let tableIndex = tables.firstIndex(where: { $0.tableNumber == tableNumber }) else {
            return .failure(.tableAssignmentFailed)
        }

        var table = tables[tableIndex]
        table.faceTimeLinkURL = faceTimeURL
        tables[tableIndex] = table

        let dbEventRef = db.collection("Events").document(eventId)

        do {
            // Update table document in Firebase
            try await dbEventRef.collection("tables").document("\(tableNumber)").setData(from: table)

            // Update the voice room document with the FaceTime URL
            let activity = TriviaEventActivity(
                eventId: eventId,
                eventTitle: event.title,
                spaceId: eventId
            )

            let tableRoomCode = TriviaEventActivity.generateTableRoomCode(
                sessionCode: activity.sessionCode,
                tableNumber: tableNumber
            )

            try await db.collection("TableVoiceRooms")
                .document(tableRoomCode)
                .updateData(["faceTimeURL": faceTimeURL])

            print("✅ [HostedEvent] Updated FaceTime link for table \(tableNumber)")
            return .success(())
        } catch {
            print("❌ [HostedEvent] Failed to update FaceTime link: \(error)")
            return .failure(.unknown)
        }
    }

    /// Get FaceTime link for a specific table
    func getFaceTimeLinkForTable(_ tableNumber: Int) -> String? {
        return tables.first(where: { $0.tableNumber == tableNumber })?.faceTimeLinkURL
    }

    // MARK: - Audio Room Integration

    func setupAudioRoomsForEvent() async {
        guard let event = currentEvent,
              let eventId = event.id else {
            print("⚠️ [HostedEvent] Cannot setup audio rooms - no current event")
            return
        }
        
        print("🎤 [HostedEvent] Setting up audio rooms for event: \(event.title)")
        
        let activity = TriviaEventActivity(
            eventId: eventId,
            eventTitle: event.title,
            spaceId: eventId
        )
        
        for table in tables {
            let tableRoomCode = TriviaEventActivity.generateTableRoomCode(
                sessionCode: activity.sessionCode,
                tableNumber: table.tableNumber
            )
            
            HostAudioManager.shared.registerRoom(
                roomCode: tableRoomCode,
                tableNumber: table.tableNumber,
                teamName: table.teamName
            )
            
            await createTableVoiceRoom(
                roomCode: tableRoomCode,
                table: table,
                sessionCode: activity.sessionCode
            )
        }
        
        let hostRoomCode = TriviaEventActivity.generateHostRoomCode(sessionCode: activity.sessionCode)
        await createHostBroadcastRoom(
            roomCode: hostRoomCode,
            sessionCode: activity.sessionCode
        )
        
        print("✅ [HostedEvent] Audio rooms setup complete")
    }
    
    func registerAudioRoomForTable(_ table: EventTable) async {
        guard let event = currentEvent,
              let eventId = event.id else { return }
        
        let activity = TriviaEventActivity(
            eventId: eventId,
            eventTitle: event.title,
            spaceId: eventId
        )
        
        let tableRoomCode = TriviaEventActivity.generateTableRoomCode(
            sessionCode: activity.sessionCode,
            tableNumber: table.tableNumber
        )
        
        HostAudioManager.shared.registerRoom(
            roomCode: tableRoomCode,
            tableNumber: table.tableNumber,
            teamName: table.teamName
        )
        
        await createTableVoiceRoom(
            roomCode: tableRoomCode,
            table: table,
            sessionCode: activity.sessionCode
        )
        
        print("✅ [HostedEvent] Registered audio room for Table \(table.tableNumber): \(tableRoomCode)")
    }
    
    private func createTableVoiceRoom(roomCode: String, table: EventTable, sessionCode: String) async {
        guard let eventId = currentEvent?.id else { return }

        var roomData: [String: Any] = [
            "roomCode": roomCode,
            "tableNumber": table.tableNumber,
            "eventId": eventId,
            "sessionCode": sessionCode,
            "teamName": table.teamName ?? "Table \(table.tableNumber)",
            "hostId": AppModel.shared.currentUserId,
            "isActive": true,
            "createdAt": Date(),
            "participantCount": table.participants.count,
            "maxParticipants": table.maxSeats
        ]

        // Only include faceTimeURL if a real FaceTime link exists
        if let faceTimeURL = table.faceTimeLinkURL {
            roomData["faceTimeURL"] = faceTimeURL
        }

        do {
            try await db.collection("TableVoiceRooms")
                .document(roomCode)
                .setData(roomData)

            print("✅ [HostedEvent] Created voice room document for \(roomCode)")
        } catch {
            print("❌ [HostedEvent] Failed to create voice room: \(error)")
        }
    }
    
    private func createHostBroadcastRoom(roomCode: String, sessionCode: String) async {
        guard let eventId = currentEvent?.id else { return }

        let roomData: [String: Any] = [
            "roomCode": roomCode,
            "roomType": "host_broadcast",
            "eventId": eventId,
            "sessionCode": sessionCode,
            "hostId": AppModel.shared.currentUserId,
            "isActive": true,
            "createdAt": Date()
            // NOTE: Host broadcast FaceTime link should be set separately via UI
        ]

        do {
            try await db.collection("HostBroadcastRooms")
                .document(roomCode)
                .setData(roomData)

            print("✅ [HostedEvent] Created host broadcast room: \(roomCode)")
        } catch {
            print("❌ [HostedEvent] Failed to create host room: \(error)")
        }
    }
    
    func getRoomCodesForParticipant(_ userId: String) async -> [String: String]? {
        guard let event = currentEvent,
              let eventId = event.id,
              let participant = participants.first(where: { $0.userId == userId }),
              let tableNumber = participant.tableNumber else { return nil }
        
        let activity = TriviaEventActivity(
            eventId: eventId,
            eventTitle: event.title,
            spaceId: eventId
        )
        
        let tableRoomCode = TriviaEventActivity.generateTableRoomCode(
            sessionCode: activity.sessionCode,
            tableNumber: tableNumber
        )
        
        return [
            "session": activity.sessionCode,
            "table": tableRoomCode,
            "table_number": "\(tableNumber)"
        ]
    }
    
    func cleanupAudioRooms() async {
        guard let event = currentEvent,
              let eventId = event.id else { return }
        
        print("🧹 [HostedEvent] Cleaning up audio rooms for event")
        
        let activity = TriviaEventActivity(
            eventId: eventId,
            eventTitle: event.title,
            spaceId: eventId
        )
        
        for table in tables {
            let tableRoomCode = TriviaEventActivity.generateTableRoomCode(
                sessionCode: activity.sessionCode,
                tableNumber: table.tableNumber
            )
            HostAudioManager.shared.unregisterRoom(tableRoomCode)
        }
        
        do {
            let batch = db.batch()
            
            for table in tables {
                let tableRoomCode = TriviaEventActivity.generateTableRoomCode(
                    sessionCode: activity.sessionCode,
                    tableNumber: table.tableNumber
                )
                let roomRef = db.collection("TableVoiceRooms").document(tableRoomCode)
                batch.updateData(["isActive": false, "endedAt": Date()], forDocument: roomRef)
            }
            
            let hostRoomCode = TriviaEventActivity.generateHostRoomCode(sessionCode: activity.sessionCode)
            let hostRoomRef = db.collection("HostBroadcastRooms").document(hostRoomCode)
            batch.updateData(["isActive": false, "endedAt": Date()], forDocument: hostRoomRef)
            
            try await batch.commit()
            print("✅ [HostedEvent] Audio rooms cleanup complete")
            
        } catch {
            print("❌ [HostedEvent] Failed to cleanup audio rooms: \(error)")
        }
    }
    
    // MARK: - Firebase Listeners
    
    private func startListeners(for eventId: String) {
        stopListeners()
        
        eventListener = db.collection("Events").document(eventId).addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ [HostedEvent] Event listener error: \(error)")
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists else {
                print("⚠️ [HostedEvent] Event document missing for id \(eventId)")
                return
            }
            
            do {
                let updatedEvent = try snapshot.data(as: CalendarEvent.self)
                Task { @MainActor in
                    self.currentEvent = updatedEvent
                }
            } catch {
                print("❌ [HostedEvent] Failed to decode event update: \(error)")
            }
        }
        
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
        eventListener?.remove()
        participantsListener?.remove()
        tablesListener?.remove()
        gameStateListener?.remove()
        eventListener = nil
        participantsListener = nil
        tablesListener = nil
        gameStateListener = nil
    }
    
    // MARK: - Statistics
    
    private func saveGameStatistics(eventId: String) async {
        let stats = GameStatistics(
            eventId: eventId,
            endTime: Date(),
            totalParticipants: participants.count,
            winningTable: getWinningTable(),
            averageScore: calculateAverageScore(),
            questionsAnswered: getQuestionsAnsweredCount()
        )
        
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
        Task { @MainActor in
            stopListeners()
        }
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
    case timeout
    case unknown
}

// MARK: - Data Models

struct GameState: Codable {
    var currentRound: Int
    var status: GameStatus
    var scores: [String: Int]
    var currentQuestion: Int?
    var trigger: String?
    var submissions: [String: AnswerSubmission]? // tableNumber -> submission
}

struct AnswerSubmission: Codable {
    var tableNumber: Int
    var submittedAt: Date
    var locked: Bool
    var answer: String? // Optional: store the actual answer if needed
}

enum GameStatus: String, Codable {
    case waiting
    case question_active
    case finished

    var displayName: String {
        switch self {
        case .waiting:
            return "Waiting to Start"
        case .question_active:
            return "Question Active"
        case .finished:
            return "Finished"
        }
    }

    var color: Color {
        switch self {
        case .waiting:
            return .orange
        case .question_active:
            return .green
        case .finished:
            return .blue
        }
    }
}

struct GameStatistics: Codable {
    var eventId: String
    var endTime: Date
    var totalParticipants: Int
    var winningTable: Int?
    var averageScore: Double
    var questionsAnswered: Int
}
