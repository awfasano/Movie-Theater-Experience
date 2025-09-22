//
//  TriviaQuestion.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/17/25.
//

// Models/TriviaQuestion.swift
import Foundation

struct TriviaQuestion: Identifiable, Codable {
    let id: String
    let questionText: String
    let options: [String]
    let correctAnswer: Int
    let points: Int
    let timeLimit: Int
    let imageURL: String?
    let category: String?
    var round: Int?
    
    init(id: String = UUID().uuidString,
         questionText: String,
         options: [String],
         correctAnswer: Int,
         points: Int = 10,
         timeLimit: Int = 30,
         imageURL: String? = nil,
         category: String? = nil,
         round: Int? = nil) {
        self.id = id
        self.questionText = questionText
        self.options = options
        self.correctAnswer = correctAnswer
        self.points = points
        self.timeLimit = timeLimit
        self.imageURL = imageURL
        self.category = category
        self.round = round
    }
}

struct TriviaGame: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let rounds: [TriviaRound]
    let totalQuestions: Int
    let createdBy: String
    let createdAt: Date
    var currentQuestionIndex: Int = 0
    
    var totalPossiblePoints: Int {
        rounds.reduce(0) { $0 + $1.totalPoints }
    }
}

struct TriviaRound: Identifiable, Codable {
    let id: String = UUID().uuidString
    let roundNumber: Int
    let title: String
    let questions: [TriviaQuestion]
    let theme: String?
    let bonusPoints: Int?
    
    var totalPoints: Int {
        questions.reduce(0) { $0 + $1.points } + (bonusPoints ?? 0)
    }
}
