//
//  TableQuestionPanel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
// Floating question panel for collaborative trivia at the table
import SwiftUI

struct TableQuestionPanel: View {
    let question: TriviaQuestion
    let timeRemaining: Int
    let tableNumber: Int
    @State private var selectedAnswer: Int? = nil
    @State private var tableVotes: [String: Int] = [:] // userId -> answer

    var body: some View {
        VStack(spacing: 20) {
            questionHeader
            Text(question.questionText)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            answerOptions
            collaborationStatus
            submitButton
        }
        .frame(width: 500, height: 400)
        .background(.regularMaterial)
        .cornerRadius(20)
        .shadow(radius: 10)
    }
    
    private var questionHeader: some View {
        HStack {
            Text("Table \(tableNumber)").font(.headline)
            Spacer()
            Text("Time: \(timeRemaining)s")
                .foregroundColor(timeRemaining < 10 ? .red : .primary)
                .fontWeight(timeRemaining < 10 ? .bold : .regular)
        }
        .padding(.horizontal)
    }
    
    private var answerOptions: some View {
        VStack(alignment: .center, spacing: 12) {
            ForEach(question.options.indices, id: \.self) { idx in
                Button(action: { selectedAnswer = idx }) {
                    HStack {
                        Text(question.options[idx])
                        Spacer()
                        if selectedAnswer == idx {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal)
                }
                .buttonStyle(.bordered)
                .background(selectedAnswer == idx ? Color.green.opacity(0.1) : .clear)
                .cornerRadius(8)
            }
        }
    }
    
    private var collaborationStatus: some View {
        VStack {
            Text("Collaboration: Live voting")
                .font(.caption)
            // You can show team vote status here
        }
    }
    
    private var submitButton: some View {
        Button("Submit Answer") {
            // Call submit logic here
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedAnswer == nil)
    }
}
