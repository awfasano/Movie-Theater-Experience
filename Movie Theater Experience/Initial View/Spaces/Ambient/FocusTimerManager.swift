//
//  FocusTimerManager.swift
//  Movie Theater Experience
//
//  Created for Ambient Focus Rooms feature.
//

import Foundation
import AudioToolbox

@MainActor
class FocusTimerManager: ObservableObject {
    static let shared = FocusTimerManager()

    // MARK: - Published Properties
    @Published var remainingSeconds: Int = 0
    @Published var totalSeconds: Int = 0
    @Published var isRunning: Bool = false
    @Published var currentPhase: TimerPhase = .idle
    @Published var selectedMode: FocusTimerMode = .simple(minutes: 25)
    @Published var completedPomodoros: Int = 0

    // MARK: - Private Properties
    private var timer: Timer?
    private var sessionStartDate: Date?

    private init() {}

    // MARK: - Computed Properties

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Controls

    func start() {
        switch selectedMode {
        case .simple(let minutes):
            totalSeconds = minutes * 60
            remainingSeconds = totalSeconds
        case .pomodoro(let focusMinutes, _):
            totalSeconds = focusMinutes * 60
            remainingSeconds = totalSeconds
        }

        currentPhase = .focus
        sessionStartDate = Date()
        completedPomodoros = 0
        startTimer()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func resume() {
        guard currentPhase != .idle else { return }
        startTimer()
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        currentPhase = .idle
        remainingSeconds = 0
        totalSeconds = 0
        sessionStartDate = nil
    }

    // MARK: - Private Methods

    private func startTimer() {
        timer?.invalidate()
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard remainingSeconds > 0 else { return }

        remainingSeconds -= 1

        if remainingSeconds <= 0 {
            handlePhaseComplete()
        }
    }

    private func handlePhaseComplete() {
        // Play completion chime
        AudioServicesPlaySystemSound(1007)

        // Record focus session if we just finished a focus phase
        if currentPhase == .focus, let startDate = sessionStartDate {
            let elapsed = Int(Date().timeIntervalSince(startDate))
            let session = FocusSession(durationSeconds: elapsed, spaceName: nil)
            FocusSessionStore.shared.recordSession(session)
        }

        switch selectedMode {
        case .simple:
            // Simple timer: just stop
            timer?.invalidate()
            timer = nil
            isRunning = false
            currentPhase = .idle

        case .pomodoro(let focusMinutes, let breakMinutes):
            if currentPhase == .focus {
                // Switch to break phase
                completedPomodoros += 1
                currentPhase = .break
                totalSeconds = breakMinutes * 60
                remainingSeconds = totalSeconds
                sessionStartDate = Date()
            } else {
                // Break is over, switch back to focus
                currentPhase = .focus
                totalSeconds = focusMinutes * 60
                remainingSeconds = totalSeconds
                sessionStartDate = Date()
            }
        }
    }
}
