//
//  TriviaGameCreatorView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/17/25.
//

import Foundation
import SwiftUI

// Local editable models for this view
private struct EditableQuestion: Identifiable {
    let id = UUID()
    var questionText: String
    var options: [String]
    var correctAnswer: Int
    var points: Int
    var timeLimit: Int

    init(questionText: String = "", options: [String] = ["", "", "", ""], correctAnswer: Int = 0, points: Int = 10, timeLimit: Int = 30) {
        self.questionText = questionText
        self.options = options
        self.correctAnswer = correctAnswer
        self.points = points
        self.timeLimit = timeLimit
    }

    // Conversion to your immutable TriviaQuestion model
    func toModel() -> TriviaQuestion {
        TriviaQuestion(questionText: questionText, options: options, correctAnswer: correctAnswer, points: points, timeLimit: timeLimit)
    }
}

private struct EditableRound: Identifiable {
    let id = UUID()
    var roundNumber: Int
    var title: String
    var theme: String?
    var bonusPoints: Int?
    var questions: [EditableQuestion] = []

    func toModel() -> TriviaRound {
        TriviaRound(roundNumber: roundNumber, title: title, questions: questions.map { $0.toModel() }, theme: theme, bonusPoints: bonusPoints)
    }
}

// Views/Admin/TriviaGameCreatorView.swift
struct TriviaGameCreatorView: View {
    @State private var gameTitle = ""
    @State private var gameDescription = ""
    @State private var rounds: [EditableRound] = []
    @State private var currentRound = EditableRound(roundNumber: 1, title: "", theme: nil, bonusPoints: nil)
    @State private var currentQuestion = EditableQuestion()
    
    var body: some View {
        NavigationStack {
            Form {
                // Game basics
                Section("Game Information") {
                    TextField("Game Title", text: $gameTitle)
                    TextField("Description", text: $gameDescription, axis: .vertical)
                }
                
                // Rounds management
                Section("Rounds") {
                    ForEach(rounds) { round in
                        RoundRowView(round: round.toModel())
                    }
                    Button("Add Round") {
                        rounds.append(currentRound)
                        currentRound = EditableRound(roundNumber: (rounds.last?.roundNumber ?? 0) + 1, title: "", theme: nil, bonusPoints: nil)
                    }
                }
                
                // Question builder
                Section("Add Question") {
                    TextField("Question", text: $currentQuestion.questionText)
                    ForEach(0..<4) { index in
                        TextField("Option \(index + 1)", text: $currentQuestion.options[index])
                    }
                    Picker("Correct Answer", selection: $currentQuestion.correctAnswer) {
                        ForEach(0..<4) { index in
                            Text("Option \(index + 1)").tag(index)
                        }
                    }
                    Stepper("Points: \(currentQuestion.points)", value: $currentQuestion.points, in: 5...100, step: 5)
                    Stepper("Time Limit: \(currentQuestion.timeLimit)s", value: $currentQuestion.timeLimit, in: 10...120, step: 10)
                    Button("Add Question To Current Round") {
                        currentRound.questions.append(currentQuestion)
                        currentQuestion = EditableQuestion()
                    }
                }
                
                // Save button
                Button("Save Game") {
                    saveGameToFirebase()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Actions
    private func saveGameToFirebase() {
        // Basic validation
        guard !gameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[Trivia] Validation failed: game title is required.")
            return
        }

        // Build the game model payload. Replace with your concrete models as needed.
        let gamePayload: [String: Any] = [
            "title": gameTitle,
            "description": gameDescription,
            "rounds": rounds.map { round in
                let model = round.toModel()
                return [
                    "roundNumber": model.roundNumber,
                    "title": model.title,
                    "theme": model.theme as Any,
                    "bonusPoints": model.bonusPoints as Any,
                    "questions": model.questions.map { q in
                        return [
                            "questionText": q.questionText,
                            "options": q.options,
                            "correctAnswer": q.correctAnswer,
                            "points": q.points,
                            "timeLimit": q.timeLimit
                        ]
                    }
                ]
            }
        ]

        // TODO: Replace this stub with real Firebase write logic (e.g., Firestore/Realtime Database)
        // Example (pseudo):
        // let db = Firestore.firestore()
        // db.collection("triviaGames").addDocument(data: gamePayload) { error in
        //     if let error = error {
        //         print("[Trivia] Failed to save game: \(error)")
        //     } else {
        //         print("[Trivia] Game saved successfully.")
        //     }
        // }

        // For now, just log to confirm wiring works.
        print("[Trivia] Prepared to save game payload: \(gamePayload)")
    }
}

// Features needed:
// - Import questions from CSV/JSON
// - Preview mode to test questions
// - Template library for common trivia formats
// - Duplicate game functionality
// - Question bank to reuse questions across games

