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
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var triviaGameManager: TriviaGameManager

    @State private var selectedTable: EventTable?
    @State private var isJoiningTable = false
    @State private var hasJoinedTable = false
    @State private var showChat = false
    @State private var showImmersiveError = false
    @State private var immersiveErrorMessage = ""
    @State private var immersiveOperationInProgress = false

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
                    }
                    
                    if currentUserTable != nil {
                        Divider()
                    }
                    
                    let selectionTitle = currentUserTable != nil ? "Switch Tables" : "Choose Your Table"
                    tableSelectionSection(title: selectionTitle, highlightTableNumber: currentUserTable?.tableNumber)
                }
                .padding()
            }
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Leave") {
                        print("🔴 [ParticipantView] Leave button tapped")
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showChat = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                    }
                }
            }
            .sheet(isPresented: $showChat) {
                NavigationStack {
                    if let eventId = hostedEventManager.currentEvent?.id {
                        EventMessagingView(eventId: eventId)
                            .environmentObject(hostedEventManager)
                            .navigationTitle("Event Chat")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") {
                                        showChat = false
                                    }
                                }
                            }
                    } else {
                        Text("Event not loaded")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .alert("Immersive Space", isPresented: $showImmersiveError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(immersiveErrorMessage)
        })
        .onAppear {
            print("🟢 [ParticipantView] View appeared")
            print("   Event: \(event.title)")
            print("   Current user ID: \(currentUserId)")
            print("   Tables count: \(hostedEventManager.tables.count)")
            print("   Current user table: \(currentUserTable?.tableNumber ?? -1)")
        }
        .task {
            // Load the trivia game when participant joins
            if let gameId = event.gameConfig?.triviaGameId {
                print("📚 [Participant] Loading trivia game: \(gameId)")
                await triviaGameManager.loadTriviaGame(gameId)
            }
        }
        .onChange(of: hostedEventManager.tables) { _, _ in
            if let current = currentUserTable {
                if selectedTable == nil || selectedTable?.tableNumber == current.tableNumber {
                    selectedTable = current
                }
            } else {
                selectedTable = nil
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

            HStack(spacing: 12) {
                Button {
                    Task { await enterImmersiveSpace() }
                } label: {
                    HStack {
                        Image(systemName: "visionpro.fill")
                        Text("Enter Immersive Space")
                        if immersiveOperationInProgress {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(immersiveOperationInProgress)

                Button {
                    Task { await exitImmersiveSpace() }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Exit Immersive Space")
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

            // Current question (if active)
            if let gameState = hostedEventManager.gameState,
               gameState.status == .question_active,
               let currentQuestion = getCurrentQuestion() {
                currentQuestionSection(question: currentQuestion, table: table)
            } else {
                // Answer submission (shown when no active question)
                answerSubmissionSection(table: table)
            }

            // Game status
            gameStatusSection
        }
    }

    // MARK: - Current Question

    private func getCurrentQuestion() -> TriviaQuestion? {
        return triviaGameManager.currentQuestion
    }

    private func currentQuestionSection(question: TriviaQuestion, table: EventTable) -> some View {
        VStack(spacing: 16) {
            Text("Answer the Question")
                .font(.title3.bold())

            TriviaQuestionView(question: question) { answer in
                // Submit the answer
                Task {
                    await submitQuestionAnswer(table: table, answer: answer)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }

    private func submitQuestionAnswer(table: EventTable, answer: String) async {
        // Submit answer with the actual answer content
        let result = await hostedEventManager.submitAnswer(tableNumber: table.tableNumber, answer: answer)

        switch result {
        case .success:
            print("✅ [Participant] Submitted answer for table \(table.tableNumber): \(answer)")
        case .failure(let error):
            print("❌ [Participant] Failed to submit answer: \(error)")
        }
    }

    // MARK: - Answer Submission

    private func answerSubmissionSection(table: EventTable) -> some View {
        let submission = hostedEventManager.getSubmissionStatus(for: table.tableNumber)
        let isLocked = submission?.locked ?? false

        return VStack(spacing: 12) {
            Text("Answer Submission")
                .font(.headline)

            if isLocked {
                // Answer is locked in
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Answer Locked In!")
                                .font(.headline)
                                .foregroundColor(.green)

                            if let submittedAt = submission?.submittedAt {
                                Text("Submitted at \(submittedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding()
                    .background(.green.opacity(0.1))
                    .cornerRadius(12)

                    Text("Waiting for other tables...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Can lock in answer
                VStack(spacing: 12) {
                    Text("Ready to submit your answer?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button {
                        Task {
                            await lockInAnswer(table: table)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "lock.circle.fill")
                            Text("Lock In Answer")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding()
                .background(.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }

    private func lockInAnswer(table: EventTable) async {
        let result = await hostedEventManager.submitAnswer(tableNumber: table.tableNumber)

        switch result {
        case .success:
            print("✅ [Participant] Locked in answer for table \(table.tableNumber)")
        case .failure(let error):
            print("❌ [Participant] Failed to lock in answer: \(error)")
        }
    }

    // MARK: - Table Selection

    private func tableSelectionSection(title: String = "Choose Your Table", highlightTableNumber: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
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
                            isSelected: selectedTable?.tableNumber == table.tableNumber,
                            isCurrent: highlightTableNumber == table.tableNumber,
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
        .onAppear {
            print("🟡 [ParticipantView] Table selection section appeared")
            print("   Available tables: \(hostedEventManager.tables.count)")
            for table in hostedEventManager.tables {
                print("   - Table \(table.tableNumber): \(table.participants.count)/\(table.maxSeats)")
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
        .onAppear {
            print("⚠️ [ParticipantView] Empty tables view shown - no tables available")
        }
    }

    private func joinTableButton(table: EventTable) -> some View {
        let isCurrentSelection = currentUserTable?.tableNumber == table.tableNumber
        let buttonTitle = isCurrentSelection ? "Currently at \(table.teamName ?? "Table \(table.tableNumber)")" : "Join \(table.teamName ?? "Table \(table.tableNumber)")"
        return Button {
            Task {
                await joinTable(table)
            }
        } label: {
            HStack {
                if isJoiningTable {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: isCurrentSelection ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                    Text(buttonTitle)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isJoiningTable || table.isFull || isCurrentSelection)
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
        print("🟡 [ParticipantView] Attempting to join table \(table.tableNumber)")
        isJoiningTable = true

        let result = await hostedEventManager.assignUserToTable(currentUserId, tableNumber: table.tableNumber)

        await MainActor.run {
            isJoiningTable = false

            switch result {
            case .success:
                print("✅ [ParticipantView] Joined table \(table.tableNumber)")
                hasJoinedTable = true
            case .failure(let error):
                print("❌ [ParticipantView] Failed to join table: \(error)")
            }
        }
    }

    // MARK: - Immersive helpers

    private func enterImmersiveSpace() async {
        await MainActor.run { immersiveOperationInProgress = true }

        do {
            let (space, resolvedSpaceId) = try await loadTriviaSpace()
            await MainActor.run {
                appModel.selectedSpace = space
                appModel.currentActiveSpace = resolvedSpaceId
            }

            let canOpen = await appModel.switchToSpace(appModel.spacesID)
            guard canOpen else {
                throw ImmersiveLaunchError.transitionFailed
            }

            let result = await openImmersiveSpace(id: appModel.spacesID)
            await MainActor.run {
                immersiveOperationInProgress = false
                handleImmersiveOpenResult(result, resolvedSpaceId: resolvedSpaceId)
            }
        } catch {
            await MainActor.run {
                immersiveOperationInProgress = false
                immersiveErrorMessage = immersiveLaunchMessage(for: error)
                showImmersiveError = true
                appModel.currentActiveSpace = nil
                appModel.selectedSpace = nil
            }
        }
    }

    private func exitImmersiveSpace() async {
        await dismissImmersiveSpace()
        await MainActor.run {
            appModel.currentActiveSpace = nil
            appModel.selectedSpace = nil
        }
    }

    private func handleImmersiveOpenResult(_ result: OpenImmersiveSpaceAction.Result, resolvedSpaceId: String) {
        switch result {
        case .opened:
            print("✅ [Participant] Opened immersive space '\(resolvedSpaceId)'")
        case .error:
            immersiveErrorMessage = "Unable to open immersive space '\(resolvedSpaceId)'."
            showImmersiveError = true
            appModel.currentActiveSpace = nil
            appModel.selectedSpace = nil
        @unknown default:
            immersiveErrorMessage = "Unknown response when opening immersive space '\(resolvedSpaceId)'."
            showImmersiveError = true
            appModel.currentActiveSpace = nil
            appModel.selectedSpace = nil
        }
    }

    private func loadTriviaSpace() async throws -> (SpaceData, String) {
        let fallbackSpaceId = "space bar"
        let trimmedEventSpaceId = (hostedEventManager.currentEvent?.spaceId ?? event.spaceId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let targetId = trimmedEventSpaceId, !targetId.isEmpty {
            do {
                let space = try await SpaceService.shared.fetchSpace(withId: targetId)
                return (space, space.id ?? targetId)
            } catch {
                print("⚠️ [Participant] Failed to load event-specific space '\(targetId)': \(error)")
                // Fall back to shared "space bar"
            }
        }

        do {
            let fallbackSpace = try await SpaceService.shared.fetchSpace(withId: fallbackSpaceId)
            return (fallbackSpace, fallbackSpace.id ?? fallbackSpaceId)
        } catch {
            print("❌ [Participant] Failed to load fallback space '\(fallbackSpaceId)': \(error)")
            throw ImmersiveLaunchError.spaceUnavailable
        }
    }

    private func immersiveLaunchMessage(for error: Error) -> String {
        if let launchError = error as? ImmersiveLaunchError {
            return launchError.localizedDescription
        } else if let serviceError = error as? SpaceServiceError {
            return serviceError.localizedDescription
        } else {
            return error.localizedDescription
        }
    }

    private enum ImmersiveLaunchError: LocalizedError {
        case transitionFailed
        case spaceUnavailable

        var errorDescription: String? {
            switch self {
            case .transitionFailed:
                return "Unable to open the immersive experience because another space is still active."
            case .spaceUnavailable:
                return "Unable to load the immersive space assets right now. Please try again."
            }
        }
    }
}

// MARK: - Table Selection Card

struct TableSelectionCard: View {
    let table: EventTable
    let isSelected: Bool
    let isCurrent: Bool
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
                } else if isCurrent {
                    Text("Currently Joined")
                        .font(.caption2.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.15))
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
