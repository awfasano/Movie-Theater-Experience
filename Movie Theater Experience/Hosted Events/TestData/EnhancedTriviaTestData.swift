//
//  EnhancedTriviaTestData.swift
//  Movie Theater Experience
//
//  Enhanced test data showcasing all question types and media support
//

import Foundation

struct EnhancedTriviaTestData {
    static let testGameId = "test-game-enhanced"

    // MARK: - Sample Questions

    static let multipleChoiceQuestions: [TriviaQuestion] = [
        TriviaQuestion(
            id: "mc1",
            questionText: "What is the capital of France?",
            questionType: .multipleChoice,
            options: ["London", "Berlin", "Paris", "Madrid"],
            correctAnswer: 2,
            points: 10,
            timeLimit: 30,
            mediaType: .none,
            category: "Geography",
            round: 1
        ),
        TriviaQuestion(
            id: "mc2",
            questionText: "Which planet is known as the Red Planet?",
            questionType: .multipleChoice,
            options: ["Mars", "Jupiter", "Saturn", "Venus"],
            correctAnswer: 0,
            points: 15,
            timeLimit: 25,
            mediaType: .image,
            mediaURL: "https://science.nasa.gov/wp-content/uploads/2023/09/mars-full-globe-jpeg.webp",
            category: "Science",
            round: 1
        ),
        TriviaQuestion(
            id: "mc3",
            questionText: "Who wrote 'Romeo and Juliet'?",
            questionType: .multipleChoice,
            options: ["Charles Dickens", "William Shakespeare", "Jane Austen", "Mark Twain"],
            correctAnswer: 1,
            points: 10,
            timeLimit: 30,
            mediaType: .none,
            category: "Literature",
            round: 1
        )
    ]

    static let trueFalseQuestions: [TriviaQuestion] = [
        TriviaQuestion(
            id: "tf1",
            questionText: "The Great Wall of China is visible from space.",
            questionType: .trueFalse,
            options: ["True", "False"],
            correctAnswer: 1, // False
            points: 10,
            timeLimit: 20,
            mediaType: .none,
            category: "Myths & Facts",
            round: 2
        ),
        TriviaQuestion(
            id: "tf2",
            questionText: "Sharks are mammals.",
            questionType: .trueFalse,
            options: ["True", "False"],
            correctAnswer: 1, // False
            points: 10,
            timeLimit: 15,
            mediaType: .none,
            category: "Biology",
            round: 2
        ),
        TriviaQuestion(
            id: "tf3",
            questionText: "Mount Everest is the tallest mountain in the world.",
            questionType: .trueFalse,
            options: ["True", "False"],
            correctAnswer: 0, // True
            points: 10,
            timeLimit: 20,
            mediaType: .image,
            mediaURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e7/Everest_North_Face_toward_Base_Camp_Tibet_Luca_Galuzzi_2006.jpg/800px-Everest_North_Face_toward_Base_Camp_Tibet_Luca_Galuzzi_2006.jpg",
            category: "Geography",
            round: 2
        )
    ]

    static let textInputQuestions: [TriviaQuestion] = [
        TriviaQuestion(
            id: "ti1",
            questionText: "Who painted the Mona Lisa?",
            questionType: .textInput,
            correctTextAnswer: "Leonardo da Vinci",
            points: 20,
            timeLimit: 45,
            mediaType: .image,
            mediaURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/e/ec/Mona_Lisa%2C_by_Leonardo_da_Vinci%2C_from_C2RMF_retouched.jpg/800px-Mona_Lisa%2C_by_Leonardo_da_Vinci%2C_from_C2RMF_retouched.jpg",
            category: "Art",
            round: 3
        ),
        TriviaQuestion(
            id: "ti2",
            questionText: "What is the chemical symbol for gold?",
            questionType: .textInput,
            correctTextAnswer: "Au",
            points: 15,
            timeLimit: 30,
            mediaType: .none,
            category: "Chemistry",
            round: 3
        ),
        TriviaQuestion(
            id: "ti3",
            questionText: "In what year did World War II end?",
            questionType: .textInput,
            correctTextAnswer: "1945",
            points: 15,
            timeLimit: 30,
            mediaType: .none,
            category: "History",
            round: 3
        )
    ]

    static let videoQuestions: [TriviaQuestion] = [
        TriviaQuestion(
            id: "vid1",
            questionText: "What movie is this famous scene from?",
            questionType: .multipleChoice,
            options: ["The Matrix", "Inception", "Interstellar", "Blade Runner"],
            correctAnswer: 0,
            points: 25,
            timeLimit: 60,
            mediaType: .video,
            mediaURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            category: "Movies",
            round: 4
        )
    ]

    // MARK: - Complete Test Rounds

    static let testRounds: [TriviaRound] = [
        TriviaRound(
            roundNumber: 1,
            title: "General Knowledge",
            questions: multipleChoiceQuestions,
            theme: "Mixed Topics",
            bonusPoints: 5
        ),
        TriviaRound(
            roundNumber: 2,
            title: "True or False",
            questions: trueFalseQuestions,
            theme: "Myths & Facts",
            bonusPoints: 10
        ),
        TriviaRound(
            roundNumber: 3,
            title: "Fill in the Blanks",
            questions: textInputQuestions,
            theme: "Quick Thinking",
            bonusPoints: 15
        ),
        TriviaRound(
            roundNumber: 4,
            title: "Movie Moments",
            questions: videoQuestions,
            theme: "Cinematic Scenes",
            bonusPoints: 20
        )
    ]

    // MARK: - Complete Test Game

    static func createTestGame() -> TriviaGame {
        let allQuestions = testRounds.flatMap { $0.questions }

        return TriviaGame(
            id: testGameId,
            title: "Enhanced Trivia Night",
            description: "A comprehensive trivia game featuring multiple choice, true/false, and text input questions with media support",
            rounds: testRounds,
            totalQuestions: allQuestions.count,
            createdBy: "test-host",
            createdAt: Date()
        )
    }

    // MARK: - Question Type Examples for Documentation

    static let examplesByType: [String: [TriviaQuestion]] = [
        "Multiple Choice": multipleChoiceQuestions,
        "True/False": trueFalseQuestions,
        "Text Input": textInputQuestions,
        "With Video": videoQuestions
    ]
}
