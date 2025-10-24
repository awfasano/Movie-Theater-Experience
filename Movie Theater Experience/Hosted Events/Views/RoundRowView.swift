//
//  RoundQuestionView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/17/25.
//

import Foundation
import SwiftUI
import Foundation

struct RoundRowView: View {
    let round: TriviaRound
    
    private var subtitle: String {
        var subtitle = "Questions: \(round.questions.count)"
        if let theme = round.theme {
            subtitle += " • Theme: \(theme)"
        }
        if let bonus = round.bonusPoints {
            subtitle += " • Bonus: +\(bonus)"
        }
        return subtitle
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Round \(round.roundNumber): \(round.title.isEmpty ? "Untitled" : round.title)")
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    let sampleQuestions = [
        TriviaQuestion(questionText: "What is the capital of France?", questionType: .multipleChoice, options: ["Paris", "London", "Berlin", "Madrid"], correctAnswer: 0, points: 10, timeLimit: 15, mediaType: .none),
        TriviaQuestion(questionText: "Who directed 'Jaws'?", questionType: .multipleChoice, options: ["Spielberg", "Scorsese", "Hitchcock", "Kubrick"], correctAnswer: 0, points: 10, timeLimit: 20, mediaType: .none),
        TriviaQuestion(questionText: "Which planet is known as the Red Planet?", questionType: .multipleChoice, options: ["Mars", "Jupiter", "Saturn", "Venus"], correctAnswer: 0, points: 10, timeLimit: 15, mediaType: .none)
    ]
    
    let sample = TriviaRound(roundNumber: 1, title: "General Knowledge", questions: sampleQuestions, theme: "Movies", bonusPoints: 5)
    
    List {
        RoundRowView(round: sample)
    }
}
