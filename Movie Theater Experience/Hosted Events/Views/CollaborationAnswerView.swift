//
//  CollaborationAnswerView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import SwiftUI

struct CollaborativeAnswerView: View {
    let question: TriviaQuestion
    let tableNumber: Int
    @EnvironmentObject private var tableManager: TableCollaborationManager

    var body: some View {
        VStack {
            Text("Choose your answer:")
                .font(.headline)
            ForEach(0..<question.options.count, id: \.self) { idx in
                Button(question.options[idx]) {
                    tableManager.submitVote(idx)
                }
                .buttonStyle(.bordered)
                .background(tableManager.userVote == idx ? Color.blue.opacity(0.2) : .clear)
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
            if let consensus = tableManager.consensus {
                HStack {
                    Text("✓ \(question.options[consensus])").foregroundColor(.green)
                    Spacer()
                    Button("Submit Final Answer") {
                        tableManager.submitConsensus()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Votes needed: \(tableManager.maxVotes - tableManager.totalVotes)")
                    .foregroundColor(.orange)
            }
        }
    }
}
