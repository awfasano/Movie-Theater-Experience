//
//  Fixed FirebaseTestDataSetup.swift
//  Movie Theater Experience
//
//  Updated to use fixed EventTable structure without nested arrays

import Foundation
import FirebaseFirestore

class FirebaseTestDataSetup {
    private let db = Firestore.firestore(database: "uploads")
    
    func setupTestData() async {
        print("🔥 Setting up Firebase test data...")
        
        do {
            // 1. Create test event
            await createTestEvent()
            
            // 2. Create test participants
            await createTestParticipants()
            
            // 3. Create test tables (FIXED to avoid nested arrays)
            await createTestTables()
            
            // 4. Create initial game state
            await createGameState()
            
            // 5. Create trivia game questions
            await createTriviaGame()
            
            print("✅ Firebase test data setup complete!")
            
        } catch {
            print("❌ Error setting up test data: \(error)")
        }
    }
    
    private func createTestEvent() async {
        print("Creating test event...")
        
        // This would be handled by your CalendarEvent system
        // For now, we'll just create the event structure in Firebase
    }
    
    private func createTestParticipants() async {
        print("Creating test participants...")
        
        let eventId = "test-trivia-event-1"
        
        let participants = [
            EventParticipant(userId: "user123", userName: "Alice Johnson", role: .participant),
            EventParticipant(userId: "user456", userName: "Bob Smith", role: .participant),
            EventParticipant(userId: "user789", userName: "Charlie Brown", role: .participant),
            EventParticipant(userId: "host001", userName: "Host Mike", role: .host)
        ]
        
        for participant in participants {
            do {
                try await db.collection("Events")
                    .document(eventId)
                    .collection("participants")
                    .document(participant.userId)
                    .setData(from: participant)
                
                print("✅ Created participant: \(participant.userName)")
            } catch {
                print("❌ Error creating participant \(participant.userName): \(error)")
            }
        }
    }
    
    // FIXED: Updated to use the new EventTable structure
    private func createTestTables() async {
        print("Creating test tables...")
        
        let eventId = "test-trivia-event-1"
        
        let tables = [
            EventTable(
                tableNumber: 1,
                tableName: "Team Alpha",
                participants: ["user123", "user456"],
                maxSeats: 4,
                currentScore: 25,
                teamName: "Lightning Bolts",
                tablePosition: SIMD3<Float>(2.0, 0.0, 1.0),
                seatPositions: [
                    SIMD3<Float>(1.5, 0.0, 0.5),
                    SIMD3<Float>(2.5, 0.0, 0.5),
                    SIMD3<Float>(1.5, 0.0, 1.5),
                    SIMD3<Float>(2.5, 0.0, 1.5)
                ]
            ),
            EventTable(
                tableNumber: 2,
                tableName: "Team Beta",
                participants: ["user789"],
                maxSeats: 4,
                currentScore: 15,
                teamName: "Thunder Hawks",
                tablePosition: SIMD3<Float>(-2.0, 0.0, 1.0),
                seatPositions: [
                    SIMD3<Float>(-2.5, 0.0, 0.5),
                    SIMD3<Float>(-1.5, 0.0, 0.5),
                    SIMD3<Float>(-2.5, 0.0, 1.5),
                    SIMD3<Float>(-1.5, 0.0, 1.5)
                ]
            ),
            EventTable(
                tableNumber: 3,
                tableName: "Team Gamma",
                participants: [],
                maxSeats: 4,
                currentScore: 0,
                teamName: "Fire Dragons",
                tablePosition: SIMD3<Float>(0.0, 0.0, 3.0),
                seatPositions: [
                    SIMD3<Float>(-0.5, 0.0, 2.5),
                    SIMD3<Float>(0.5, 0.0, 2.5),
                    SIMD3<Float>(-0.5, 0.0, 3.5),
                    SIMD3<Float>(0.5, 0.0, 3.5)
                ]
            ),
            EventTable(
                tableNumber: 4,
                tableName: "Team Delta",
                participants: [],
                maxSeats: 4,
                currentScore: 0,
                teamName: "Ice Phoenix",
                tablePosition: SIMD3<Float>(0.0, 0.0, -1.0),
                seatPositions: [
                    SIMD3<Float>(-0.5, 0.0, -1.5),
                    SIMD3<Float>(0.5, 0.0, -1.5),
                    SIMD3<Float>(-0.5, 0.0, -0.5),
                    SIMD3<Float>(0.5, 0.0, -0.5)
                ]
            )
        ]
        
        for table in tables {
            do {
                try await db.collection("Events")
                    .document(eventId)
                    .collection("tables")
                    .document("\(table.tableNumber)")
                    .setData(from: table)
                
                print("✅ Created table: \(table.teamName ?? "Table \(table.tableNumber)")")
            } catch {
                print("❌ Error creating table \(table.tableNumber): \(error)")
            }
        }
    }
    
    private func createGameState() async {
        print("Creating game state...")
        
        let eventId = "test-trivia-event-1"
        
        let gameState = GameState(
            currentRound: 2,
            status: .question_active,
            scores: [
                "1": 25,
                "2": 15,
                "3": 0,
                "4": 0
            ],
            currentQuestion: 3,
            trigger: "Question 3 is now active"
        )
        
        do {
            try await db.collection("Events")
                .document(eventId)
                .collection("gameState")
                .document("current")
                .setData(from: gameState)
            
            print("✅ Created game state")
        } catch {
            print("❌ Error creating game state: \(error)")
        }
    }
    
    private func createTriviaGame() async {
        print("Creating trivia game using EnhancedTriviaTestData...")

        // Use the enhanced test data
        let triviaGame = EnhancedTriviaTestData.createTestGame()
        
        do {
            try await db.collection("TriviaGames")
                .document(triviaGame.id)
                .setData(from: triviaGame)

            print("✅ Created enhanced trivia game: \(triviaGame.title)")
            print("   - \(triviaGame.rounds.count) rounds")
            print("   - \(triviaGame.totalQuestions) total questions")
            print("   - Total possible points: \(triviaGame.totalPossiblePoints)")
        } catch {
            print("❌ Error creating trivia game: \(error)")
        }
    }
    
    // MARK: - Helper method to add sample votes for testing
    
    func addSampleVotes() async {
        print("Adding sample votes...")
        
        let eventId = "test-trivia-event-1"
        
        // Add some sample votes for table 1
        let table1Votes = [
            ("user123", 2), // Alice votes for option 3
            ("user456", 1)  // Bob votes for option 2
        ]
        
        for (userId, vote) in table1Votes {
            do {
                try await db.collection("Events")
                    .document(eventId)
                    .collection("tables")
                    .document("1")
                    .collection("votes")
                    .document(userId)
                    .setData(["vote": vote])
                
                print("✅ Added vote for \(userId): \(vote)")
            } catch {
                print("❌ Error adding vote: \(error)")
            }
        }
        
        // Add a sample submission
        let submissionData: [String: Any] = [
            "answer": 2,
            "submittedBy": "user123",
            "timestamp": Date()
        ]
        
        do {
            try await db.collection("Events")
                .document(eventId)
                .collection("tables")
                .document("1")
                .collection("submissions")
                .document("question3")
                .setData(submissionData)
            
            print("✅ Added sample submission")
        } catch {
            print("❌ Error adding submission: \(error)")
        }
    }
}

// MARK: - Usage in your app

/*
To use this in your app, call it from somewhere like your AppModel or a debug view:

Button("Setup Test Data") {
    Task {
        let setup = FirebaseTestDataSetup()
        await setup.setupTestData()
        await setup.addSampleVotes()
    }
}
*/
