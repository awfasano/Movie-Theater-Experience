//
//  TriviaTestDataGenerator.swift
//  Movie Theater Experience
//
//  Generates realistic test data for trivia events
//

import Foundation
import FirebaseFirestore
import simd

@MainActor
public class TriviaTestDataGenerator {
    public static let shared = TriviaTestDataGenerator()
    private let db = FirebaseEventManager.uploadsDb

    private init() {}

    // MARK: - Main Test Data Generation

    /// Creates a complete test trivia event with all necessary data
    func createTestTriviaEvent() async throws -> CalendarEvent {
        print("🎮 [TestData] Creating test trivia event...")

        // Create the event
        let event = createMockEvent()

        // Upload to Firebase
        let eventRef = db.collection("Events").document()
        let eventData = event.toFirebaseData()

        print("📤 [TestData] Saving event data:")
        print("   - eventType: \(eventData["eventType"] ?? "nil")")
        print("   - status: \(eventData["status"] ?? "nil")")
        print("   - title: \(eventData["title"] ?? "nil")")

        try await eventRef.setData(eventData)

        var savedEvent = event
        savedEvent.id = eventRef.documentID

        print("✅ [TestData] Created event: \(savedEvent.title) (ID: \(eventRef.documentID))")
        print("   - Database: uploads")
        print("   - Collection: Events")

        // Create tables
        await createTestTables(for: savedEvent, in: eventRef)

        // Create trivia game
        await createTestTriviaGame(for: savedEvent)

        print("🎉 [TestData] Test trivia event fully created!")
        return savedEvent
    }

    // MARK: - Event Creation

    private func createMockEvent() -> CalendarEvent {
        let now = Date()
        let startTime = now.addingTimeInterval(300) // Starts in 5 minutes
        let endTime = startTime.addingTimeInterval(3600) // 1 hour long

        let tableConfig = TableConfiguration(
            maxTables: 6,
            maxSeatsPerTable: 4,
            layoutType: .circular
        )

        let gameConfig = GameConfiguration(
            triviaGameId: "test-trivia-game-001",
            totalRounds: 3,
            pointsPerQuestion: 10,
            questionTimeLimit: 30
        )

        var event = CalendarEvent(
            title: "🎯 Friday Night Trivia",
            description: "Join us for an exciting trivia night! Test your knowledge, compete with friends, and win prizes!",
            startTime: startTime,
            endTime: endTime
        )

        event.eventType = .hostedTrivia
        event.status = .scheduled
        event.maxParticipants = 24
        event.currentParticipants = 0
        event.requiresRegistration = true
        event.hostId = "host-test-123"
        event.hostName = "Trivia Master"
        event.tableConfiguration = tableConfig
        event.gameConfig = gameConfig
        event.spaceId = "trivia-space-001"

        return event
    }

    // MARK: - Table Creation

    private func createTestTables(for event: CalendarEvent, in eventRef: DocumentReference) async {
        guard let tableConfig = event.tableConfiguration else { return }

        print("🪑 [TestData] Creating \(tableConfig.maxTables) tables...")

        let tableNames = [
            "Thunder Squad",
            "Brain Busters",
            "Quiz Masters",
            "The Thinkers",
            "Trivia Titans",
            "Knowledge Ninjas"
        ]

        for i in 1...tableConfig.maxTables {
            let table = createMockTable(
                number: i,
                maxSeats: tableConfig.maxSeatsPerTable,
                teamName: i <= tableNames.count ? tableNames[i-1] : nil
            )

            do {
                try await eventRef.collection("tables")
                    .document("\(i)")
                    .setData(from: table)
                print("  ✓ Created table \(i): \(table.teamName ?? "Table \(i)")")
            } catch {
                print("  ✗ Failed to create table \(i): \(error)")
            }
        }
    }

    private func createMockTable(number: Int, maxSeats: Int, teamName: String?) -> EventTable {
        // Create circular layout
        let radius: Float = 5.0
        let angle = Float(number - 1) * (2 * .pi / 6)
        let tablePosition = SIMD3<Float>(
            radius * cos(angle),
            1.0,
            radius * sin(angle)
        )

        // Create seat positions around the table
        var seatPositions: [SIMD3<Float>] = []
        let seatRadius: Float = 0.8
        for seat in 0..<maxSeats {
            let seatAngle = Float(seat) * (2 * .pi / Float(maxSeats))
            let seatPos = SIMD3<Float>(
                tablePosition.x + seatRadius * cos(seatAngle),
                tablePosition.y,
                tablePosition.z + seatRadius * sin(seatAngle)
            )
            seatPositions.append(seatPos)
        }

        return EventTable(
            tableNumber: number,
            tableName: teamName,
            participants: [],
            maxSeats: maxSeats,
            currentScore: 0,
            teamName: teamName,
            tablePosition: tablePosition,
            seatPositions: seatPositions,
            faceTimeLinkURL: nil // Host will set this later
        )
    }

    // MARK: - Trivia Game Creation

    private func createTestTriviaGame(for event: CalendarEvent) async {
        guard let gameConfig = event.gameConfig else { return }

        print("📚 [TestData] Creating trivia game...")

        let rounds = createTestRounds(count: gameConfig.totalRounds)
        let totalQuestions = rounds.reduce(0) { $0 + $1.questions.count }

        let game = TriviaGame(
            id: gameConfig.triviaGameId,
            title: "General Knowledge Trivia",
            description: "A mix of history, science, pop culture, and more!",
            rounds: rounds,
            totalQuestions: totalQuestions,
            createdBy: "Test Data Generator",
            createdAt: Date(),
            currentQuestionIndex: 0
        )

        do {
            try await db.collection("TriviaGames")
                .document(gameConfig.triviaGameId)
                .setData(from: game)
            print("✅ [TestData] Created trivia game with \(game.rounds.count) rounds")
        } catch {
            print("❌ [TestData] Failed to create trivia game: \(error)")
        }
    }

    private func createTestRounds(count: Int) -> [TriviaRound] {
        var rounds: [TriviaRound] = []

        for roundNum in 1...count {
            let round = TriviaRound(
                roundNumber: roundNum,
                title: "Round \(roundNum)",
                questions: createTestQuestions(for: roundNum),
                theme: roundNum == 1 ? "General Knowledge" : (roundNum == 2 ? "Science & Nature" : "Pop Culture"),
                bonusPoints: roundNum == count ? 5 : nil
            )
            rounds.append(round)
        }

        return rounds
    }

    private func createTestQuestions(for round: Int) -> [TriviaQuestion] {
        let questionsData: [[String: Any]] = [
            [
                "text": "What is the capital of France?",
                "options": ["London", "Paris", "Berlin", "Madrid"],
                "correct": 1
            ],
            [
                "text": "How many planets are in our solar system?",
                "options": ["7", "8", "9", "10"],
                "correct": 1
            ],
            [
                "text": "Who painted the Mona Lisa?",
                "options": ["Van Gogh", "Picasso", "Da Vinci", "Monet"],
                "correct": 2
            ],
            [
                "text": "What year did World War II end?",
                "options": ["1943", "1944", "1945", "1946"],
                "correct": 2
            ],
            [
                "text": "What is the largest ocean on Earth?",
                "options": ["Atlantic", "Indian", "Arctic", "Pacific"],
                "correct": 3
            ]
        ]

        var questions: [TriviaQuestion] = []

        for (index, data) in questionsData.enumerated() {
            let question = TriviaQuestion(
                id: "r\(round)q\(index + 1)",
                questionText: data["text"] as! String,
                options: data["options"] as! [String],
                correctAnswer: data["correct"] as! Int,
                points: 10,
                timeLimit: 30,
                round: round
            )
            questions.append(question)
        }

        return questions
    }

    // MARK: - Quick Test Methods

    /// Creates multiple test events for different dates
    func createMultipleTestEvents(count: Int = 3) async throws -> [CalendarEvent] {
        var events: [CalendarEvent] = []

        for i in 0..<count {
            let days = TimeInterval(i * 86400) // i days in seconds
            var event = createMockEvent()
            event.title = "Trivia Night #\(i + 1)"
            event.startTime = event.startTime.addingTimeInterval(days)
            event.endTime = event.endTime.addingTimeInterval(days)

            let eventRef = db.collection("Events").document()
            try await eventRef.setData(event.toFirebaseData())
            event.id = eventRef.documentID

            await createTestTables(for: event, in: eventRef)

            events.append(event)
            print("✅ [TestData] Created event \(i + 1)/\(count)")
        }

        return events
    }

    /// Deletes all test events
    func deleteAllTestEvents() async throws {
        print("🗑️ [TestData] Deleting all test events...")

        let snapshot = try await db.collection("Events").getDocuments()

        for doc in snapshot.documents {
            // Delete subcollections first
            let tablesSnapshot = try await doc.reference.collection("tables").getDocuments()
            for tableDoc in tablesSnapshot.documents {
                try await tableDoc.reference.delete()
            }

            // Delete the event
            try await doc.reference.delete()
        }

        print("✅ [TestData] Deleted \(snapshot.documents.count) test events")
    }
}
