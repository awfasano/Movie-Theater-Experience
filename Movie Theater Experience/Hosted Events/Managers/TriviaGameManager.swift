//
//  TriviaGameManager.swift
//  Movie Theater Experience
//
//  Manages trivia game flow and state
//

import Foundation
import FirebaseFirestore
import SwiftUI

@MainActor
class TriviaGameManager: ObservableObject {
    static let shared = TriviaGameManager()
    
    @Published private(set) var currentGame: TriviaGame?
    @Published private(set) var currentQuestion: TriviaQuestion?
    @Published private(set) var gameState: GameState?
    @Published private(set) var timeRemaining: Int = 0

    private let db = Firestore.firestore(database: "uploads")
    
    private init() {}

    @MainActor
    func loadTriviaGame(_ gameId: String) async {
        do {
            let doc = try await db.collection("TriviaGames")
                .document(gameId)
                .getDocument()
            
            if let data = doc.data() {
                currentGame = try Firestore.Decoder().decode(TriviaGame.self, from: data)
                print("✅ Loaded trivia game: \(currentGame?.title ?? "Unknown")")
                return
            }
        } catch {
            print("❌ Error loading trivia game: \(error)")
        }

        loadFallbackGame(for: gameId)
    }
    
    @MainActor
    func startQuestion(_ questionId: String) async {
        guard let game = currentGame else { return }
        
        for round in game.rounds {
            if let question = round.questions.first(where: { $0.id == questionId }) {
                currentQuestion = question
                timeRemaining = question.timeLimit
                startTimer()
                
                print("✅ Started question: \(question.questionText)")
                break
            }
        }
    }
    
    private func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                self.timeRemaining -= 1
                if self.timeRemaining <= 0 {
                    timer.invalidate()
                    await self.endQuestion()
                }
            }
        }
    }
    
    @MainActor
    func endQuestion() async {
        currentQuestion = nil
        await calculateScores()
        
        // Move to next question or round
        if let game = currentGame {
            var updatedGame = game
            updatedGame.currentQuestionIndex += 1
            currentGame = updatedGame
        }
    }
    
    @MainActor
    func submitAnswer(from tableNumber: Int, answer: Int) async {
        guard let question = currentQuestion,
              let eventId = HostedEventManager.shared.currentEvent?.id else { return }
        
        let submission: [String: Any] = [
            "tableNumber": tableNumber,
            "answer": answer,
            "questionId": question.id,
            "timestamp": Date(),
            "points": answer == question.correctAnswer ? question.points : 0
        ]
        
        do {
            try await db.collection("Events")
                .document(eventId)
                .collection("submissions")
                .document("\(tableNumber)_\(question.id)")
                .setData(submission)
        } catch {
            print("❌ Error submitting answer: \(error)")
        }
    }
    
    @MainActor
    func calculateScores() async {
        guard let eventId = HostedEventManager.shared.currentEvent?.id,
              let question = currentQuestion else { return }
        
        do {
            let submissions = try await db.collection("Events")
                .document(eventId)
                .collection("submissions")
                .whereField("questionId", isEqualTo: question.id)
                .getDocuments()
            
            for doc in submissions.documents {
                if let tableNumber = doc.data()["tableNumber"] as? Int,
                   let points = doc.data()["points"] as? Int {
                    
                    // Update scores in game state via HostedEventManager
                    await HostedEventManager.shared.awardPoints(
                        to: tableNumber,
                        points: points
                    )
                }
            }
        } catch {
            print("❌ Error calculating scores: \(error)")
        }
    }
    
    func nextQuestion() async {
        guard let game = currentGame else {
            print("⚠️ No current game loaded")
            return
        }
        
        // Find next question
        let currentIndex = game.currentQuestionIndex
        var nextQuestionId: String?
        
        for round in game.rounds {
            for question in round.questions {
                if question.id.contains("\(currentIndex + 1)") {
                    nextQuestionId = question.id
                    break
                }
            }
            if nextQuestionId != nil { break }
        }
        
        if let questionId = nextQuestionId {
            await startQuestion(questionId)
        } else {
            print("⚠️ No next question found")
        }
    }
    
    func nextRound() async {
        guard let game = currentGame else {
            print("⚠️ No current game loaded")
            return
        }
        
        var updatedGame = game
        let currentRoundNumber = game.rounds.first?.roundNumber ?? 0
        
        if let nextRound = game.rounds.first(where: { $0.roundNumber == currentRoundNumber + 1 }) {
            updatedGame.currentQuestionIndex = 0
            currentGame = updatedGame
            
            // Start first question of next round
            if let firstQuestion = nextRound.questions.first {
                await startQuestion(firstQuestion.id)
            }
            
            print("✅ [TriviaGame] Advanced to round \(nextRound.roundNumber)")
        } else {
            print("⚠️ No next round available")
        }
    }
    
    // MARK: - Helper methods
    
    func getCurrentQuestionForDisplay() -> TriviaQuestion? {
        return currentQuestion
    }
    
    func isGameActive() -> Bool {
        return currentGame != nil && timeRemaining > 0
    }
    
    func getGameProgress() -> (currentQuestion: Int, totalQuestions: Int) {
        guard let game = currentGame else {
            return (0, 0)
        }
        
        let totalQuestions = game.rounds.reduce(0) { $0 + $1.questions.count }
        return (game.currentQuestionIndex, totalQuestions)
    }
    
    private func loadFallbackGame(for gameId: String) {
        guard gameId == EnhancedTriviaTestData.testGameId else {
            print("⚠️ No fallback trivia game available for id \(gameId)")
            return
        }
        
        let fallbackGame = EnhancedTriviaTestData.createTestGame()
        currentGame = fallbackGame
        print("ℹ️ Loaded fallback trivia game locally: \(fallbackGame.title)")
    }
}
