//
//  TriviaQuestion.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/17/25.
//

// Models/TriviaQuestion.swift
import Foundation

enum QuestionType: String, Codable {
    case multipleChoice = "multiple_choice"
    case textInput = "text_input"
    case trueFalse = "true_false"
}

enum MediaType: String, Codable {
    case none
    case image
    case video
}

struct TriviaQuestion: Identifiable, Codable {
    let id: String
    let questionText: String
    let questionType: QuestionType
    let options: [String] // Used for multiple choice/true-false
    let correctAnswer: Int // Index for multiple choice, or 0/1 for true/false
    let correctTextAnswer: String? // Used for text input questions
    let points: Int
    let timeLimit: Int

    // Media support
    let mediaType: MediaType
    let mediaURL: String? // Can be image or video URL

    let category: String?
    var round: Int?

    // Legacy support
    var imageURL: String? {
        mediaType == .image ? mediaURL : nil
    }

    init(id: String = UUID().uuidString,
         questionText: String,
         questionType: QuestionType = .multipleChoice,
         options: [String] = [],
         correctAnswer: Int = 0,
         correctTextAnswer: String? = nil,
         points: Int = 10,
         timeLimit: Int = 30,
         mediaType: MediaType = .none,
         mediaURL: String? = nil,
         category: String? = nil,
         round: Int? = nil) {
        self.id = id
        self.questionText = questionText
        self.questionType = questionType
        self.options = options
        self.correctAnswer = correctAnswer
        self.correctTextAnswer = correctTextAnswer
        self.points = points
        self.timeLimit = timeLimit
        self.mediaType = mediaType
        self.mediaURL = mediaURL
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
