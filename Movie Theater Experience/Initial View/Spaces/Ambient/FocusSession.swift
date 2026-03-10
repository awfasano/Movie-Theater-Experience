//
//  FocusSession.swift
//  Movie Theater Experience
//
//  Created for Ambient Focus Rooms feature.
//

import Foundation

struct FocusSession: Codable, Identifiable {
    let id: UUID
    let date: Date
    let durationSeconds: Int
    let spaceName: String?

    init(durationSeconds: Int, spaceName: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.durationSeconds = durationSeconds
        self.spaceName = spaceName
    }
}

@MainActor
class FocusSessionStore: ObservableObject {
    static let shared = FocusSessionStore()

    @Published private(set) var sessions: [FocusSession] = []

    private let storageKey = "focusSessions"

    init() {
        loadSessions()
    }

    var todayTotal: Int {
        let calendar = Calendar.current
        return sessions
            .filter { calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    var weekTotal: Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessions
            .filter { $0.date >= weekAgo }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    func recordSession(_ session: FocusSession) {
        sessions.append(session)
        saveSessions()
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FocusSession].self, from: data) else { return }
        sessions = decoded
    }

    private func saveSessions() {
        // Keep last 90 days only
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        sessions = sessions.filter { $0.date >= cutoff }

        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
