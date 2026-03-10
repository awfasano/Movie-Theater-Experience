//
//  FocusTimerView.swift
//  Movie Theater Experience
//
//  Created for Ambient Focus Rooms feature.
//

import SwiftUI

struct FocusTimerView: View {
    @EnvironmentObject var timerManager: FocusTimerManager
    @StateObject private var sessionStore = FocusSessionStore.shared

    // Ring appearance
    private let ringSize: CGFloat = 200
    private let ringLineWidth: CGFloat = 12

    var body: some View {
        VStack(spacing: 24) {
            // MARK: - Title
            Text("Focus Timer")
                .font(.title2)
                .fontWeight(.semibold)

            // MARK: - Progress Ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: ringLineWidth)
                    .frame(width: ringSize, height: ringSize)

                // Progress ring
                Circle()
                    .trim(from: 0, to: timerManager.progress)
                    .stroke(
                        phaseColor,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timerManager.progress)

                // Time display
                VStack(spacing: 4) {
                    Text(timerManager.formattedTime)
                        .font(.system(size: 44, weight: .light, design: .monospaced))
                        .contentTransition(.numericText())

                    // Phase label (only in pomodoro mode)
                    if case .pomodoro = timerManager.selectedMode,
                       timerManager.currentPhase != .idle {
                        Text(timerManager.currentPhase.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(phaseColor)
                    }
                }
            }

            // Pomodoro counter
            if case .pomodoro = timerManager.selectedMode,
               timerManager.completedPomodoros > 0 {
                HStack(spacing: 6) {
                    ForEach(0..<timerManager.completedPomodoros, id: \.self) { _ in
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                    }
                }
            }

            // MARK: - Control Buttons
            HStack(spacing: 20) {
                if timerManager.currentPhase == .idle {
                    // Start button
                    Button(action: {
                        timerManager.start()
                    }) {
                        Label("Start", systemImage: "play.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    // Pause / Resume toggle
                    Button(action: {
                        if timerManager.isRunning {
                            timerManager.pause()
                        } else {
                            timerManager.resume()
                        }
                    }) {
                        Label(
                            timerManager.isRunning ? "Pause" : "Resume",
                            systemImage: timerManager.isRunning ? "pause.fill" : "play.fill"
                        )
                        .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(timerManager.isRunning ? .orange : .green)

                    // Reset button
                    Button(action: {
                        timerManager.reset()
                    }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }

            // MARK: - Preset Selector (only when idle)
            if timerManager.currentPhase == .idle {
                VStack(spacing: 8) {
                    Text("Presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        ForEach(FocusTimerMode.presets) { preset in
                            Button(action: {
                                timerManager.selectedMode = preset
                            }) {
                                Text(preset.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(timerManager.selectedMode == preset ? .blue : .gray)
                        }
                    }
                }
            }

            Divider()
                .padding(.horizontal, 20)

            // MARK: - Session Stats
            HStack(spacing: 16) {
                Label(formatDuration(sessionStore.todayTotal), systemImage: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("|")
                    .foregroundStyle(.quaternary)

                Label(formatDuration(sessionStore.weekTotal), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 350, height: 500)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }

    // MARK: - Helpers

    private var phaseColor: Color {
        switch timerManager.currentPhase {
        case .focus: return .green
        case .break: return .blue
        case .idle: return .gray
        }
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
