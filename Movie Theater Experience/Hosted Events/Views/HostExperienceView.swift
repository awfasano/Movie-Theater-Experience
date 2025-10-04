//
//  HostExperienceView.swift
//  Movie Theater Experience
//
//  Main host experience - control panel and game management
//

import SwiftUI

struct HostExperienceView: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hostedEventManager: HostedEventManager

    @State private var selectedTab: HostTab = .overview
    @State private var showFaceTimeSetup = false

    enum HostTab: String, CaseIterable {
        case overview = "Overview"
        case tables = "Tables"
        case game = "Game"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .tables: return "table.furniture.fill"
            case .game: return "gamecontroller.fill"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    ForEach(HostTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                ScrollView {
                    Group {
                        switch selectedTab {
                        case .overview:
                            overviewTab
                        case .tables:
                            tablesTab
                        case .game:
                            gameTab
                        case .settings:
                            settingsTab
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Host Control Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showFaceTimeSetup) {
                TableFaceTimeLinkSetupView()
                    .environmentObject(hostedEventManager)
            }
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        VStack(spacing: 20) {
            // Event info
            eventInfoCard

            // Quick stats
            statsGrid

            // Quick actions
            quickActionsCard
        }
    }

    private var eventInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: event.eventIcon)
                    .font(.title)
                    .foregroundColor(event.eventColor)

                VStack(alignment: .leading) {
                    Text(event.title)
                        .font(.headline)
                    Text(event.formattedTimeRange)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                StatusBadge(status: event.status)
            }

            Divider()

            Text(event.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            HostStatCard(
                title: "Participants",
                value: "\(hostedEventManager.participants.count)",
                icon: "person.2.fill",
                color: .blue
            )

            HostStatCard(
                title: "Tables",
                value: "\(hostedEventManager.tables.count)",
                icon: "table.furniture.fill",
                color: .green
            )

            if let gameState = hostedEventManager.gameState {
                HostStatCard(
                    title: "Round",
                    value: "\(gameState.currentRound)",
                    icon: "number.circle.fill",
                    color: .orange
                )

                HostStatCard(
                    title: "Question",
                    value: "\(gameState.currentQuestion ?? 0)",
                    icon: "questionmark.circle.fill",
                    color: .purple
                )
            }
        }
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            VStack(spacing: 8) {
                Button {
                    showFaceTimeSetup = true
                } label: {
                    HStack {
                        Image(systemName: "video.fill")
                        Text("Set Up FaceTime Links")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await hostedEventManager.setupAudioRoomsForEvent()
                    }
                } label: {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                        Text("Initialize Audio Rooms")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await hostedEventManager.startGame()
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Game")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(hostedEventManager.gameState != nil)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    // MARK: - Tables Tab

    private var tablesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tables Overview")
                .font(.headline)

            if hostedEventManager.tables.isEmpty {
                emptyTablesView
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(hostedEventManager.tables.sorted(by: { $0.tableNumber < $1.tableNumber })) { table in
                        HostTableCard(table: table)
                    }
                }
            }
        }
    }

    private var emptyTablesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "table.furniture")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No tables created yet")
                .font(.headline)

            Text("Tables will appear here once the event is set up")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Game Tab

    private var gameTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Game Controls")
                .font(.headline)

            if let gameState = hostedEventManager.gameState {
                gameControlsCard(state: gameState)
            } else {
                noGameView
            }
        }
    }

    private func gameControlsCard(state: GameState) -> some View {
        VStack(spacing: 16) {
            // Current state
            VStack(spacing: 12) {
                HStack {
                    Text("Round \(state.currentRound)")
                        .font(.title2.bold())
                    Spacer()
                    Text(state.status.displayName)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(state.status.color.opacity(0.2))
                        .foregroundColor(state.status.color)
                        .cornerRadius(8)
                }

                if let question = state.currentQuestion {
                    Text("Question \(question)")
                        .font(.headline)
                }
            }
            .padding()
            .background(.blue.opacity(0.1))
            .cornerRadius(12)

            // Controls
            VStack(spacing: 8) {
                Button {
                    Task {
                        await TriviaGameManager.shared.nextQuestion()
                    }
                } label: {
                    HStack {
                        Image(systemName: "forward.fill")
                        Text("Next Question")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await TriviaGameManager.shared.nextRound()
                    }
                } label: {
                    HStack {
                        Image(systemName: "forward.end.fill")
                        Text("Next Round")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await hostedEventManager.endGame()
                    }
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("End Game")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
    }

    private var noGameView: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Game not started")
                .font(.headline)

            Button {
                Task {
                    await hostedEventManager.startGame()
                }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Game")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            VStack(spacing: 12) {
                Button {
                    showFaceTimeSetup = true
                } label: {
                    HStack {
                        Image(systemName: "video")
                        Text("FaceTime Link Setup")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    // Audio settings
                } label: {
                    HStack {
                        Image(systemName: "speaker.wave.2")
                        Text("Audio Settings")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.bordered)

                Divider()

                Button(role: .destructive) {
                    Task {
                        await hostedEventManager.endGame()
                        dismiss()
                    }
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("End Event")
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Host Stat Card

struct HostStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title.bold())
                .foregroundColor(.primary)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Host Table Card

struct HostTableCard: View {
    let table: EventTable

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(table.teamName ?? "Table \(table.tableNumber)")
                        .font(.headline)

                    Text("\(table.participants.count)/\(table.maxSeats) participants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(table.currentScore) pts")
                    .font(.title3.bold())
                    .foregroundColor(.blue)
            }

            if table.faceTimeLinkURL != nil {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("FaceTime link configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("FaceTime link not set")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Preview

#if DEBUG
struct HostExperienceView_Previews: PreviewProvider {
    static var previews: some View {
        HostExperienceView(event: CalendarEvent(
            title: "Friday Night Trivia",
            description: "Test event",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        ))
        .environmentObject(HostedEventManager.shared)
    }
}
#endif
