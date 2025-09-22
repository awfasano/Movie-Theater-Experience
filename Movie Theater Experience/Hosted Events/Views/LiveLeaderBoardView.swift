//
//  LiveLeaderBoardView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/17/25.
//

import Foundation
import SwiftUI

// Views/Leaderboard/LiveLeaderboardView.swift
struct LiveLeaderboardView: View {
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @State private var animateChanges = false
    
    var sortedTables: [(table: EventTable, score: Int)] {
        guard let gameState = hostedEventManager.gameState else { return [] }
        let tables = hostedEventManager.tables
        return tables.compactMap { table in
            let score = gameState.scores["\(table.tableNumber)"] ?? 0
            return (table: table, score: score)
        }
        .sorted { $0.score > $1.score }
    }
    
    // Helper to determine if a table is the current user's table
    private func isUserTable(_ table: EventTable) -> Bool {
        // Try to infer user's table from gameState if possible; otherwise, always false.
        // If your project later adds a concrete way to identify the user's table, update this logic.
        guard let gameState = hostedEventManager.gameState else { return false }

        // If GameState has a mapping from userId -> tableNumber, try to consult it.
        // Since `currentUserTableNumber` doesn't exist (compile error), we conservatively return false.
        _ = gameState // silence unused warning if not used in future updates
        return false
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header with live indicator
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.red, lineWidth: 2)
                            .scaleEffect(animateChanges ? 2 : 1)
                            .opacity(animateChanges ? 0 : 1)
                            .animation(.easeOut(duration: 1).repeatForever(), value: animateChanges)
                    )
                Text("LIVE SCORES")
                    .font(.headline)
                    .foregroundColor(.red)
            }
            
            // Leaderboard
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(sortedTables.enumerated()), id: \.element.table.id) { index, item in
                        LeaderboardRowView(
                            position: index + 1,
                            table: item.table,
                            score: item.score,
                            isCurrentUserTable: isUserTable(item.table)
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    }
                }
                .padding()
            }
            
            // Current round/question indicator
            if let gs = hostedEventManager.gameState {
                HStack {
                    Text("Round \(gs.currentRound)")
                    Divider().frame(height: 20)
                    Text("Question \(gs.currentQuestion)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .frame(width: 400, height: 600)
        .background(.regularMaterial)
        .cornerRadius(20)
        .onAppear {
            animateChanges = true
        }
    }
}

struct LeaderboardRowView: View {
    let position: Int
    let table: EventTable
    let score: Int
    let isCurrentUserTable: Bool
    
    @State private var scoreChanged = false
    
    var body: some View {
        HStack {
            // Position medal/number
            PositionIndicator(position: position)
            
            // Table info
            VStack(alignment: .leading) {
                Text(table.teamName ?? "Table \(table.tableNumber)")
                    .font(.headline)
                Text("\(table.participants.count) players")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Score with animation
            Text("\(score)")
                .font(.title2.bold())
                .foregroundColor(scoreColor)
                .scaleEffect(scoreChanged ? 1.3 : 1.0)
                .animation(.spring(response: 0.3), value: scoreChanged)
        }
        .padding()
        .background(backgroundStyle)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentUserTable ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onChange(of: score) { _, _ in
            scoreChanged = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                scoreChanged = false
            }
        }
    }
    
    var scoreColor: Color {
        switch position {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .primary
        }
    }
    
    var backgroundStyle: some ShapeStyle {
        if isCurrentUserTable {
            return Color.blue.opacity(0.1)
        }
        return Color.gray.opacity(0.1)
    }
}

struct PositionIndicator: View {
    let position: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(colorForPosition)
                .frame(width: 36, height: 36)
            Text("\(position)")
                .font(.subheadline.bold())
                .foregroundColor(.white)
        }
        .accessibilityLabel("Position \(position)")
    }

    private var colorForPosition: Color {
        switch position {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue
        }
    }
}
