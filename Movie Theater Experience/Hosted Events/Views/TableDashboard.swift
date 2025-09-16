//
//  TableDashboard.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import SwiftUI

struct TableDashboard: View {
    let tableNumber: Int
    // Normally uses a TableCollaborationManager
    @State private var teamMembers: [TeamMember] = [] // Stub data
    @State private var score: Int = 0
    @State private var round: Int = 1
    @State private var canSkip = true
    @State private var hintUsed = false

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
            Text("Round \(round)").font(.subheadline)
        }
    }
    
    private var teamMembersStatus: some View {
        VStack(alignment: .leading) {
            Text("Team Status").font(.headline)
            ForEach(teamMembers) { member in
                HStack {
                    Circle().fill(member.hasVoted ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(member.userName).font(.subheadline)
                    Spacer()
                    if member.hasVoted {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    } else {
                        Image(systemName: "clock.fill").foregroundColor(.orange)
                    }
                }
            }
        }
    }
    
    private var scoreDisplay: some View {
        HStack {
            Text("Score: \(score)")
            Spacer()
        }.font(.title3.bold())
    }
    
    private var quickActions: some View {
        HStack {
            Button("Request Hint") { /* Logic */ }
                .buttonStyle(.bordered)
                .disabled(hintUsed)
            Button("Skip Question") { /* Logic */ }
                .buttonStyle(.bordered)
                .disabled(!canSkip)
        }
    }
}

// Stub team member type for dashboard
struct TeamMember: Identifiable {
    let id: String
    let userName: String
    let hasVoted: Bool
}
