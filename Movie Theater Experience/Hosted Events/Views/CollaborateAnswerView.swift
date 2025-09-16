//
//  CollaborateAnswerView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import SwiftUI

struct CollaborativeAnswerView: View {
    // Use an environment manager or pass needed voting/collab objects
    let question: TriviaQuestion
    let tableNumber: Int
    // This view would typically use a TableCollaborationManager for real voting sync
    @State private var userVote: Int? = nil
    @State private var votes: [Int: Int] = [:] // answerIndex: count
    @State private var teamConsensus: Int? = nil
    @State private var totalVotes: Int = 0
    let maxVotes = 4 // For 4 seat table

    var body: some View {
        VStack {
            Text("Choose your answer:")
                .font(.headline)
            ForEach(0..<question.options.count, id: \.self) { idx in
                Button(question.options[idx]) {
                    userVote = idx
                    // Broadcast vote to teammates (stub)
                }
                .buttonStyle(.bordered)
                .background(userVote == idx ? Color.blue.opacity(0.2) : .clear)
                .cornerRadius(6)
            }
            Divider().padding(.vertical, 8)
            consensusSection
        }
        .frame(width: 320)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(14)
    }
    
    private var consensusSection: some View {
        VStack {
            Text("Table Decision:")
                .font(.subheadline)
            if let consensus = teamConsensus {
                HStack {
                    Text("✓ \(question.options[consensus])").foregroundColor(.green)
                    Spacer()
                    Button("Submit Final Answer") {
                        // Submit logic
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Votes needed: \(maxVotes - totalVotes)")
                    .foregroundColor(.orange)
            }
        }
    }
}
