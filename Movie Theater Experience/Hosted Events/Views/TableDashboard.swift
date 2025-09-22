//
//  TableDashboard.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

// Refactor TableDashboard to use TableCollaborationManager for live team status and scores
import SwiftUI

struct TableDashboard: View {
    let tableNumber: Int
    @EnvironmentObject private var tableManager: TableCollaborationManager

    var body: some View {
        VStack(spacing: 16) {
            tableHeader
            teamMembersStatus
            scoreDisplay
            quickActions
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
        .frame(width: 300)
    }
    
    private var tableHeader: some View {
        HStack {
            Text("Table \(tableNumber)").font(.headline)
            Spacer()
            Text("Round \(tableManager.question.round ?? 1)").font(.subheadline)
        }
    }
    
    private var teamMembersStatus: some View {
        VStack(alignment: .leading) {
            Text("Team Status").font(.headline)
            ForEach(tableManager.teamMembers) { member in
                HStack {
                    Circle().fill(tableManager.userVotes[member.id] != nil ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(member.userName).font(.subheadline)
                    Spacer()
                    if let vote = tableManager.userVotes[member.id], vote < tableManager.question.options.count {
                        Text(tableManager.question.options[vote])
                    } else {
                        Text("…")
                    }
                }
            }
        }
    }
    
    private var scoreDisplay: some View {
        HStack {
            Text("Score: \(tableManager.teamMembers.count * 10)") // Example: 10 pts per member
            Spacer()
        }.font(.title3.bold())
    }
    
    private var quickActions: some View {
        HStack {
            Button("Request Hint") { /* Logic */ }
                .buttonStyle(.bordered)
                .disabled(false)
            Button("Skip Question") { /* Logic */ }
                .buttonStyle(.bordered)
                .disabled(false)
        }
    }
}
