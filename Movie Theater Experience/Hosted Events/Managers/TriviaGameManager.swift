//
//  TriviaGameManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
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

    @MainActor
    func loadTriviaGame(_ gameId: String) async {
        do {
            let doc = try await db.collection("TriviaGames")
                .document(gameId)
                .getDocument()
            
            if let data = doc.data() {
                currentGame = try Firestore.Decoder().decode(TriviaGame.self, from: data)
                print("✅ Loaded trivia game: \(currentGame?.title ?? "Unknown")")
            }
        } catch {
            print("❌ Error loading trivia game: \(error)")
        }
    }
    
    @MainActor
    func startQuestion(_ questionId: String) async {
        guard let game = currentGame else { return }
        
        for round in game.rounds {
            if let question = round.questions.first(where: { $0.id == questionId }) {
                currentQuestion = question
                timeRemaining = question.timeLimit
                startTimer()
                
                // Notify all participants
                await notifyQuestionStart(question)
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
                    
                    // Update scores in game state
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
    
    private func notifyQuestionStart(_ question: TriviaQuestion) async {
        // Send notification through SharePlay or Firebase
        await TriviaSharePlayManager.shared.sendMessage(question)
    }

    
    func nextQuestion() async { }
    func nextRound() async { }
}
