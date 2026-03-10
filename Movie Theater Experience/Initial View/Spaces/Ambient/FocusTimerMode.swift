//
//  FocusTimerMode.swift
//  Movie Theater Experience
//
//  Created for Ambient Focus Rooms feature.
//

import Foundation

enum FocusTimerMode: Equatable, Identifiable {
    case simple(minutes: Int)
    case pomodoro(focusMinutes: Int, breakMinutes: Int)

    var id: String {
        switch self {
        case .simple(let m): return "simple_\(m)"
        case .pomodoro(let f, let b): return "pomodoro_\(f)_\(b)"
        }
    }

    var displayName: String {
        switch self {
        case .simple(let m): return "\(m) min"
        case .pomodoro(let f, let b): return "\(f)/\(b) Pomodoro"
        }
    }

    static let presets: [FocusTimerMode] = [
        .simple(minutes: 5),
        .simple(minutes: 15),
        .simple(minutes: 25),
        .simple(minutes: 50),
        .pomodoro(focusMinutes: 25, breakMinutes: 5)
    ]
}

enum TimerPhase: String {
    case focus = "Focus"
    case `break` = "Break"
    case idle = "Idle"
}
