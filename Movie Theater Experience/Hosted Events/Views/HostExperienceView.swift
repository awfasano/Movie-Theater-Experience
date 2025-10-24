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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var triviaGameManager: TriviaGameManager
    @ObservedObject private var spaceService = SpaceService.shared

    @State private var selectedTab: HostTab = .overview
    @State private var showFaceTimeSetup = false
    @State private var showImmersiveError = false
    @State private var immersiveErrorMessage = ""
    @State private var immersiveOperationInProgress = false
    @State private var isUpdatingSpaceSelection = false
    @State private var spaceSelectionInFlightId: String?
    @State private var spaceSelectionError: String?

    enum HostTab: String, CaseIterable {
        case overview = "Overview"
        case tables = "Tables"
        case game = "Game"
        case chat = "Chat"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .tables: return "table.furniture.fill"
            case .game: return "gamecontroller.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
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
                Group {
                    switch selectedTab {
                    case .overview:
                        ScrollView {
                            overviewTab
                                .padding()
                        }
                    case .tables:
                        ScrollView {
                            tablesTab
                                .padding()
                        }
                    case .game:
                        ScrollView {
                            gameTab
                                .padding()
                        }
                    case .chat:
                        if let eventId = hostedEventManager.currentEvent?.id {
                            EventMessagingView(eventId: eventId)
                                .environmentObject(hostedEventManager)
                        } else {
                            Text("Event not loaded")
                                .foregroundColor(.secondary)
                        }
                    case .settings:
                        ScrollView {
                            settingsTab
                                .padding()
                        }
                    }
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
            .alert("Unable to update immersive space", isPresented: $showImmersiveError, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(immersiveErrorMessage)
            })
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
            // Open Full Host Controls Button
            Button {
                openWindow(id: "hostControls")
            } label: {
                HStack {
                    Image(systemName: "macwindow.badge.plus")
                    Text("Open Full Host Controls Window")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.headline)
                .padding()
                .background(.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            Divider()

            Text("Quick Game Controls")
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
                    // Start the game
                    let result = await hostedEventManager.startGame()

                    // Load trivia game
                    if case .success = result,
                       let gameId = event.gameConfig?.triviaGameId {
                        await triviaGameManager.loadTriviaGame(gameId)
                    }
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

            spaceSelectionSection

            if let error = spaceSelectionError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if isUpdatingSpaceSelection {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating immersive space…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

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

                Button {
                    Task { await enterImmersiveSpace() }
                } label: {
                    HStack {
                        Image(systemName: "visionpro.fill")
                        Text("Enter Immersive Space")
                        Spacer()
                        if immersiveOperationInProgress {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(immersiveOperationInProgress)

                Button {
                    Task { await exitImmersiveSpace() }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Exit Immersive Space")
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
        .onAppear {
            if spaceService.spaces.isEmpty {
                spaceService.fetchSpaces()
            }
            
            Task {
                let needsSpaceBar = await MainActor.run {
                    !(spaceService.spaces.contains { trimmedOrNil($0.id) == "space bar" })
                }
                
                if needsSpaceBar {
                    try? await SpaceService.shared.fetchSpace(withId: "space bar")
                }
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

            if let faceTimeURL = table.faceTimeLinkURL {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("FaceTime configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        // Join as Host button
                        Button {
                            if let url = URL(string: faceTimeURL) {
                                Task {
                                    let success = await UIApplication.shared.open(url)
                                    if success {
                                        print("✅ [Host] Joined table \(table.tableNumber) FaceTime call")
                                    } else {
                                        print("❌ [Host] Failed to open FaceTime link")
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "video.fill")
                                Text("Join as Host")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        // Copy Link button
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = faceTimeURL
                            #endif
                            print("📋 [Host] Copied FaceTime link for table \(table.tableNumber)")
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
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

// MARK: - Immersive helpers

extension HostExperienceView {
    private var spaceSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Immersive Space")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Choose the immersive environment for this event. Participants will join the selected space.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let name = currentSpaceDisplayName {
                Text("Currently selected: \(name)")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if featuredSpaces.isEmpty {
                Text(spaceService.spaces.isEmpty ? "Loading spaces…" : "No immersive spaces available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(featuredSpaces.enumerated()), id: \.offset) { item in
                        let space = item.element
                        let spaceId = trimmedOrNil(space.id) ?? ""
                        let isActive = currentSpaceId == spaceId

                        Button {
                            if !isActive, !spaceId.isEmpty {
                                selectSpace(spaceId)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(space.spaceName)
                                        .font(.headline)
                                    Text(space.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else if isUpdatingSpaceSelection,
                                          spaceSelectionInFlightId == spaceId {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isActive ? Color.blue.opacity(0.12) : Color.gray.opacity(0.06))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(spaceId.isEmpty || isUpdatingSpaceSelection)
                    }
                }
            }

            Divider()
                .padding(.top, 4)
        }
    }

    private var featuredSpaces: [SpaceData] {
        let preferredIds = ["space bar", "space lounge", "space plaza"]
        let spaces = spaceService.spaces.filter { trimmedOrNil($0.id) != nil }

        var ordered: [SpaceData] = []

        for id in preferredIds {
            if let match = spaces.first(where: { $0.id == id }), !ordered.contains(match) {
                ordered.append(match)
            }
        }

        for space in spaces where !ordered.contains(space) {
            ordered.append(space)
        }

        return Array(ordered.prefix(3))
    }

    private var currentSpaceId: String? {
        if let active = trimmedOrNil(hostedEventManager.currentEvent?.spaceId) {
            return active
        }
        return trimmedOrNil(event.spaceId)
    }
    
    private var currentSpaceDisplayName: String? {
        guard let currentId = currentSpaceId else { return nil }
        if let match = spaceService.spaces.first(where: { trimmedOrNil($0.id) == currentId }) {
            return match.spaceName
        }
        return nil
    }

    private func selectSpace(_ spaceId: String) {
        if isUpdatingSpaceSelection || spaceId.isEmpty {
            return
        }

        Task {
            await MainActor.run {
                isUpdatingSpaceSelection = true
                spaceSelectionError = nil
                spaceSelectionInFlightId = spaceId
            }

            let result = await hostedEventManager.updateEventSpace(to: spaceId)

            await MainActor.run {
                isUpdatingSpaceSelection = false
                spaceSelectionInFlightId = nil

                switch result {
                case .success:
                    spaceSelectionError = nil
                case .failure(let error):
                    spaceSelectionError = hostedEventErrorDescription(error)
                }
            }
        }
    }

    private func hostedEventErrorDescription(_ error: HostedEventError) -> String {
        switch error {
        case .eventNotFound:
            return "Event could not be found."
        case .joinFailed:
            return "You do not have permission to change the immersive space."
        case .tableAssignmentFailed:
            return "Unable to update the immersive space right now."
        case .insufficientPermissions:
            return "Insufficient permissions to update the immersive space."
        case .timeout:
            return "Timed out while updating the immersive space."
        case .unknown:
            fallthrough
        @unknown default:
            return "An unknown error occurred when updating the immersive space."
        }
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

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
                let didOpen = handleImmersiveOpenResult(result, resolvedSpaceId: resolvedSpaceId)
                if didOpen {
                    openHostControlsForEventIfNeeded()
                }
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

    private func handleImmersiveOpenResult(_ result: OpenImmersiveSpaceAction.Result, resolvedSpaceId: String) -> Bool {
        switch result {
        case .opened:
            print("✅ [Host] Opened immersive space '\(resolvedSpaceId)'")
            return true
        case .error:
            immersiveErrorMessage = "Unable to open immersive space '\(resolvedSpaceId)'."
            showImmersiveError = true
            appModel.currentActiveSpace = nil
            appModel.selectedSpace = nil
            return false
        @unknown default:
            immersiveErrorMessage = "Unknown response when opening immersive space '\(resolvedSpaceId)'."
            showImmersiveError = true
            appModel.currentActiveSpace = nil
            appModel.selectedSpace = nil
            return false
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
                print("⚠️ [Host] Failed to load event-specific space '\(targetId)': \(error)")
                // Fall back to shared "space bar"
            }
        }

        do {
            let fallbackSpace = try await SpaceService.shared.fetchSpace(withId: fallbackSpaceId)
            return (fallbackSpace, fallbackSpace.id ?? fallbackSpaceId)
        } catch {
            print("❌ [Host] Failed to load fallback space '\(fallbackSpaceId)': \(error)")
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

    private func openHostControlsForEventIfNeeded() {
        let activeEvent = hostedEventManager.currentEvent ?? event
        guard activeEvent.isHostedEvent else {
            return
        }

        openWindow(id: "hostControls")
    }
}
