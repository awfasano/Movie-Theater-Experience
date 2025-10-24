//
//  Fixed CollaborativeAnswerView.swift
//  Movie Theater Experience
//
//  With SharePlay real-time feedback - Fixed errors
//

import SwiftUI

struct CollaborativeAnswerView: View {
    let question: TriviaQuestion
    let tableNumber: Int
    @EnvironmentObject private var tableManager: TableCollaborationManager
    @State private var pulseAnimations: [Int: Bool] = [:]

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            questionText
            answerOptions
            Divider().padding(.vertical, 8)
            consensusSection
        }
        .frame(width: 350)
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Table \(tableNumber)")
                    .font(.headline)
                    .foregroundColor(.primary)

                // Show live indicator if people are voting
                if tableManager.totalVotes > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Live")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer()

            // Live voting indicator
            if tableManager.totalVotes > 0 {
                VStack(alignment: .trailing) {
                    Text("Team Votes")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("\(tableManager.totalVotes)/\(tableManager.maxVotes)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var questionText: some View {
        Text("Choose your answer:")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    
    private var answerOptions: some View {
        VStack(spacing: 12) {
            ForEach(0..<question.options.count, id: \.self) { idx in
                answerButton(for: idx)
            }
        }
    }
    
    private func answerButton(for index: Int) -> some View {
        Button(action: {
            tableManager.submitVote(index)
            triggerPulseAnimation(for: index)
        }) {
            HStack {
                Text(question.options[index])
                    .font(.body)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                // Vote count indicator
                let voteCount = voteCount(for: index)
                if voteCount > 0 {
                    Text("\(voteCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.blue))
                }
                
                // Selection indicator
                if tableManager.userVote == index {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .background(backgroundColor(for: index))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor(for: index), lineWidth: 2)
        )
        .scaleEffect(scaleEffect(for: index))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: tableManager.userVote)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pulseAnimations[index] ?? false)
    }
    
    private func voteCount(for index: Int) -> Int {
        // Count votes for this answer from userVotes
        let count = tableManager.userVotes.values.filter { $0 == index }.count
        return count
    }
    
    private func backgroundColor(for index: Int) -> Color {
        if tableManager.userVote == index {
            return Color.blue.opacity(0.3)
        } else if tableManager.consensus == index {
            return Color.green.opacity(0.2)
        } else if tableManager.userVotes.values.contains(index) {
            return Color.orange.opacity(0.1)
        }
        return Color.gray.opacity(0.05)
    }

    private func borderColor(for index: Int) -> Color {
        if tableManager.userVote == index {
            return Color.blue
        } else if tableManager.consensus == index {
            return Color.green
        } else if tableManager.userVotes.values.contains(index) {
            return Color.orange
        }
        return Color.clear
    }
    
    private func scaleEffect(for index: Int) -> CGFloat {
        if tableManager.userVote == index {
            return 1.05
        } else if pulseAnimations[index] == true {
            return 1.03
        }
        return 1.0
    }
    
    private func triggerPulseAnimation(for index: Int) {
        pulseAnimations[index] = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pulseAnimations[index] = false
        }
    }
    
    private var consensusSection: some View {
        VStack(spacing: 12) {
            Text("Team Decision")
                .font(.headline)
                .foregroundColor(.primary)
            
            if tableManager.answerSubmitted {
                // Show submitted answer
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Submitted: \(question.options[tableManager.finalAnswer ?? 0])")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                
            } else if let consensus = tableManager.consensus {
                // Show consensus ready for submission
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("Consensus: \(question.options[consensus])")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    
                    Button("Submit Final Answer") {
                        tableManager.submitConsensus()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tableManager.answerSubmitted)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                
            } else {
                // Show voting progress
                VStack(spacing: 8) {
                    let totalVotes = tableManager.totalVotes
                    let votesNeeded = tableManager.maxVotes - totalVotes

                    if votesNeeded > 0 {
                        Text("Votes needed: \(votesNeeded)")
                            .font(.body)
                            .foregroundColor(.orange)
                    } else {
                        Text("Waiting for consensus...")
                            .font(.body)
                            .foregroundColor(.blue)
                    }

                    // Progress bar
                    ProgressView(value: Float(totalVotes), total: Float(tableManager.maxVotes))
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))

                    // Live activity indicator
                    if tableManager.totalVotes > 0 {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Team is voting")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CollaborativeAnswerView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleQuestion = TriviaQuestion(
            questionText: "What is the capital of France?",
            questionType: .multipleChoice,
            options: ["London", "Berlin", "Paris", "Madrid"],
            correctAnswer: 2,
            points: 10,
            timeLimit: 30,
            mediaType: .none
        )
        
        CollaborativeAnswerView(
            question: sampleQuestion,
            tableNumber: 1
        )
        .environmentObject(TableCollaborationManager(
            tableNumber: 1,
            maxVotes: 4,
            question: sampleQuestion,
            userId: "test-user",
            eventId: "test-event"
        ))
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
