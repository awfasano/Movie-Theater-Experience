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

    func loadTriviaGame(_ gameId: String) async { }
    func startQuestion(_ questionId: String) async { }
    func endQuestion() async { }
    func submitAnswer(from tableNumber: Int, answer: Int) async { }
    func calculateScores() async { }
    func nextQuestion() async { }
    func nextRound() async { }
}
