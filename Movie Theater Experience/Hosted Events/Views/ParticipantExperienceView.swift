//
//  ParticipantExperienceView.swift
//  Movie Theater Experience
//
//  Main participant experience - table selection and gameplay
//

import SwiftUI

struct ParticipantExperienceView: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hostedEventManager: HostedEventManager

    @State private var selectedTable: EventTable?
    @State private var isJoiningTable = false
    @State private var hasJoinedTable = false

    var currentUserId: String {
        AppModel.shared.currentUserId.isEmpty ? "test-user-\(UUID().uuidString.prefix(8))" : AppModel.shared.currentUserId
    }

    var currentUserTable: EventTable? {
        hostedEventManager.tables.first(where: { $0.participants.contains(currentUserId) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    if let userTable = currentUserTable {
                        currentTableSection(table: userTable)
                    } else {
                        tableSelectionSection
                    }
                }
                .padding()
            }
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Leave") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Welcome, Participant!")
                .font(.title2.bold())

            if currentUserTable == nil {
                Text("Select a table to join with your friends")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Current Table

    private func currentTableSection(table: EventTable) -> some View {
        VStack(spacing: 20) {
            // Table info
            VStack(spacing: 12) {
                Text("You're at")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(table.teamName ?? "Table \(table.tableNumber)")
                    .font(.title.bold())
                    .foregroundColor(.blue)

                HStack(spacing: 20) {
                    VStack {
                        Text("\(table.participants.count)")
                            .font(.title2.bold())
                        Text("Players")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text("\(table.currentScore)")
                            .font(.title2.bold())
                        Text("Score")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(.blue.opacity(0.1))
            .cornerRadius(16)

            // FaceTime join
            TableFaceTimeJoinView(tableNumber: table.tableNumber)
                .environmentObject(hostedEventManager)

            // Game status
            gameStatusSection
        }
    }

    // MARK: - Table Selection

    private var tableSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Your Table")
                .font(.headline)

            if hostedEventManager.tables.isEmpty {
                emptyTablesView
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(hostedEventManager.tables.sorted(by: { $0.tableNumber < $1.tableNumber })) { table in
                        TableSelectionCard(
                            table: table,
                            isSelected: selectedTable?.id == table.id,
                            onSelect: {
                                selectedTable = table
                            },
                            onJoin: {
                                Task {
                                    await joinTable(table)
                                }
                            }
                        )
                    }
                }
            }

            if let selected = selectedTable {
                joinTableButton(table: selected)
            }
        }
    }

    private var emptyTablesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "table.furniture")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No tables available yet")
                .font(.headline)

            Text("The host is setting up tables")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }

    private func joinTableButton(table: EventTable) -> some View {
        Button {
            Task {
                await joinTable(table)
            }
        } label: {
            HStack {
                if isJoiningTable {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Join \(table.teamName ?? "Table \(table.tableNumber)")")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isJoiningTable || table.isFull)
    }

    // MARK: - Game Status

    private var gameStatusSection: some View {
        VStack(spacing: 12) {
            Text("Game Status")
                .font(.headline)

            if let gameState = hostedEventManager.gameState {
                VStack(spacing: 8) {
                    HStack {
                        Text("Round:")
                        Spacer()
                        Text("\(gameState.currentRound)")
                            .bold()
                    }

                    HStack {
                        Text("Question:")
                        Spacer()
                        Text("\(gameState.currentQuestion ?? 0)")
                            .bold()
                    }

                    HStack {
                        Text("Status:")
                        Spacer()
                        Text(gameState.status.displayName)
                            .bold()
                            .foregroundColor(gameState.status.color)
                    }
                }
                .font(.subheadline)
            } else {
                Text("Waiting for game to start...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func joinTable(_ table: EventTable) async {
        isJoiningTable = true

        let result = await hostedEventManager.assignUserToTable(currentUserId, tableNumber: table.tableNumber)

        await MainActor.run {
            isJoiningTable = false

            switch result {
            case .success:
                print("✅ [Participant] Joined table \(table.tableNumber)")
                hasJoinedTable = true
            case .failure(let error):
                print("❌ [Participant] Failed to join table: \(error)")
            }
        }
    }
}

// MARK: - Table Selection Card

struct TableSelectionCard: View {
    let table: EventTable
    let isSelected: Bool
    let onSelect: () -> Void
    let onJoin: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Table icon
                Image(systemName: "table.furniture.fill")
                    .font(.title)
                    .foregroundColor(table.isFull ? .secondary : .blue)

                // Table name
                Text(table.teamName ?? "Table \(table.tableNumber)")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                // Occupancy
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption)
                    Text("\(table.participants.count)/\(table.maxSeats)")
                        .font(.caption)
                }
                .foregroundColor(.secondary)

                // Status
                if table.isFull {
                    Text("Full")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red)
                        .cornerRadius(4)
                } else {
                    Text("\(table.availableSeats) seats left")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? .blue.opacity(0.1) : .gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(table.isFull)
    }
}

// MARK: - Preview

#if DEBUG
struct ParticipantExperienceView_Previews: PreviewProvider {
    static var previews: some View {
        ParticipantExperienceView(event: CalendarEvent(
            title: "Friday Night Trivia",
            description: "Test event",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        ))
        .environmentObject(HostedEventManager.shared)
    }
}
#endif
