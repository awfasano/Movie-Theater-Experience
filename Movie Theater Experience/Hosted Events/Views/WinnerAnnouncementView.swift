//
//  WinnerAnnouncementView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/17/25.
//

import Foundation
import SwiftUI

struct WinnerAnnouncementView: View {
    let winningTable: EventTable
    let finalScores: [(table: EventTable, score: Int)]
    @State private var showConfetti = false
    @State private var animationPhase = 0
    
    var body: some View {
        ZStack {
            // Background effects
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 30) {
                // Trophy animation
                TrophyView()
                    .scaleEffect(animationPhase >= 1 ? 1 : 0)
                    .rotationEffect(.degrees(animationPhase >= 1 ? 360 : 0))
                    .animation(.spring(response: 0.6), value: animationPhase)
                
                // Winner announcement
                VStack(spacing: 10) {
                    Text("🎉 WINNERS! 🎉")
                        .font(.largeTitle.bold())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(animationPhase >= 2 ? 1 : 0)
                    
                    Text(winningTable.teamName ?? "Table \(winningTable.tableNumber)")
                        .font(.title)
                        .opacity(animationPhase >= 3 ? 1 : 0)
                    
                    Text("\(finalScores.first?.score ?? 0) points")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .opacity(animationPhase >= 3 ? 1 : 0)
                }
                
                // Final leaderboard
                if animationPhase >= 4 {
                    FinalLeaderboardView(scores: finalScores)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Action buttons
                if animationPhase >= 5 {
                    HStack(spacing: 20) {
                        Button("Play Again") {
                            // Reset game logic
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Exit") {
                            // Exit logic
                        }
                        .buttonStyle(.bordered)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(40)
        }
        .onAppear {
            animateSequence()
        }
    }
    
    private func animateSequence() {
        for phase in 1...5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(phase) * 0.5) {
                withAnimation {
                    animationPhase = phase
                    if phase == 2 {
                        showConfetti = true
                    }
                }
            }
        }
    }
}
