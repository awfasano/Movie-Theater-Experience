//
//  Enhanced TriviaHostControlsView.swift
//  Movie Theater Experience
//
//  Host controls with SharePlay integration and Audio Control tab
//

import SwiftUI

struct TriviaHostControlsView: View {
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var triviaGameManager: TriviaGameManager
    @EnvironmentObject private var personaManager: PersonaTableManager
    @EnvironmentObject private var triviaImmersiveManager: TriviaImmersiveManager
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab = 0

    // Timer state
    @State private var timerSeconds: Int = 30
    @State private var timerRunning: Bool = false
    @State private var remainingSeconds: Int = 30
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $selectedTab) {

            sharePlayControlsTab
                .tabItem {
                    Label("Overview", systemImage: "chart.bar.fill")
                }
                .tag(0)
            
            gameControlsTab
                .tabItem {
                    Label("Game", systemImage: "gamecontroller")
                }
                .tag(1)
            
            participantManagementTab
                .tabItem {
                    Label("Participants", systemImage: "person.3")
                }
                .tag(2)
            
            broadcastTab
                .tabItem {
                    Label("Broadcast", systemImage: "megaphone")
                }
                .tag(3)
            
            audioControlsTab
                .tabItem {
                    Label("Audio Control", systemImage: "speaker.wave.3")
                }
                .tag(4)
        }
        .frame(minWidth: 800, minHeight: 600)
        
        
            #if DEBUG
            VStack(spacing: 20) {
                Text("Debug Tools")
                    .font(.title2.bold())
                
                FirebaseDebugButton()
                
                Button("Open SharePlay Test") {
                    openWindow(id: "sharePlayDebug")
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding()
            .tabItem {
                Label("Debug", systemImage: "hammer")
            }
            #endif
    }
    
    // MARK: - Audio Controls Tab
    
    private var audioControlsTab: some View {
        HostMasterControlView()
            .environmentObject(hostedEventManager)
    }
    
    // MARK: - Overview Tab

    private var sharePlayControlsTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Event Overview")
                    .font(.largeTitle.bold())
                    .padding(.top)
                
                // Connection Status
                connectionStatusCard
                
                // Session Controls
                sessionControlsCard
                
                // Participants Overview
                participantsCard
                
                // Live Notifications
                liveNotificationsCard
                
                Spacer()
            }
            .padding()
        }
    }
    
    private var connectionStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Circle()
                    .fill(hostedEventManager.currentEvent != nil ? .green : .red)
                    .frame(width: 16, height: 16)

                Text(hostedEventManager.currentEvent != nil ? "Event Active" : "No Event")
                    .font(.title2.bold())
                    .foregroundColor(hostedEventManager.currentEvent != nil ? .green : .red)

                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Participants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(hostedEventManager.participants.count)")
                        .font(.title3.bold())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Event ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(hostedEventManager.currentEvent?.id ?? "None")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var sessionControlsCard: some View {
        VStack(spacing: 16) {
            Text("Event Management")
                .font(.headline)

            if hostedEventManager.currentEvent == nil {
                Text("No active event")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()

                Text("Start an event from the Events tab to begin")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

            } else {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Event Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(hostedEventManager.currentEvent?.title ?? "Unknown")
                                .font(.body.bold())
                        }
                        Spacer()
                    }

                    Button(action: {
                        Task {
                            await hostedEventManager.setupAudioRoomsForEvent()
                        }
                    }) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("Initialize Audio Rooms")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var participantsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Event Participants")
                .font(.headline)

            if hostedEventManager.participants.isEmpty {
                Text("No participants connected")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()

            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(hostedEventManager.participants) { participant in
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(participant.userName)
                                    .font(.caption)
                                    .lineLimit(1)
                                if let tableNum = participant.tableNumber {
                                    Text("Table \(tableNum)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var liveNotificationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Broadcasts")
                .font(.headline)

            if let lastTrigger = hostedEventManager.gameState?.trigger, !lastTrigger.isEmpty {
                HStack {
                    Image(systemName: "megaphone.fill")
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(lastTrigger)
                            .font(.body)
                            .fontWeight(.medium)

                        Text("Latest Notification")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(.blue.opacity(0.1))
                .cornerRadius(8)
            } else {
                Text("No notifications sent yet")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }

            Text("Use the Broadcast tab to send messages to all participants")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Game Controls Tab
    
    private var gameControlsTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Game Controls")
                    .font(.largeTitle.bold())
                    .padding(.top)

                // Game State Display
                gameStateCard

                // Current Question Display
                currentQuestionCard

                // Game Flow Controls
                gameFlowCard

                // Timer Controls
                timerControlCard

                // Submission Tracking
                submissionTrackingCard

                // Scoring Controls
                scoringCard

                Spacer()
            }
            .padding()
        }
    }
    
    private var currentQuestionCard: some View {
        VStack(spacing: 16) {
            Text("Current Question")
                .font(.headline)

            if let question = triviaGameManager.currentQuestion {
                VStack(alignment: .leading, spacing: 16) {
                    // Question text
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Question \(question.round ?? 0)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(question.points) points")
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                        }

                        Text(question.questionText)
                            .font(.title3.bold())
                            .padding()
                            .background(.blue.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // Media preview if available
                    if question.mediaType == .image, let imageURL = question.mediaURL {
                        Text("🖼️ Image: \(imageURL)")
                            .font(.caption)
                            .foregroundColor(.purple)
                            .padding(8)
                            .background(.purple.opacity(0.1))
                            .cornerRadius(6)
                    } else if question.mediaType == .video, let videoURL = question.mediaURL {
                        Text("🎥 Video: \(videoURL)")
                            .font(.caption)
                            .foregroundColor(.purple)
                            .padding(8)
                            .background(.purple.opacity(0.1))
                            .cornerRadius(6)
                    }

                    // Options
                    if !question.options.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Answer Options:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)

                                    Text(option)
                                        .font(.body)

                                    if index == question.correctAnswer {
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(8)
                                .background(index == question.correctAnswer ? .green.opacity(0.1) : .gray.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    } else if let textAnswer = question.correctTextAnswer {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Correct Answer:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(textAnswer)
                                .font(.body.bold())
                                .padding(8)
                                .background(.green.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }

                    // Question metadata
                    HStack {
                        Label("\(question.timeLimit)s", systemImage: "clock")
                        Spacer()
                        if let category = question.category {
                            Label(category, systemImage: "tag")
                        }
                        Spacer()
                        Label(question.questionType.rawValue, systemImage: "questionmark.circle")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } else if triviaGameManager.currentGame != nil {
                Text("No active question - Press 'Next Question' to start")
                    .font(.body)
                    .foregroundColor(.orange)
                    .padding()
            } else {
                Text("No trivia game loaded")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var gameStateCard: some View {
        VStack(spacing: 16) {
            Text("Current Game State")
                .font(.headline)
            
            if let gameState = hostedEventManager.gameState {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Round")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(gameState.currentRound)")
                                .font(.title.bold())
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .center) {
                            Text("Question")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(gameState.currentQuestion ?? 0)")
                                .font(.title.bold())
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Status")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(gameState.status.rawValue.capitalized)
                                .font(.body.bold())
                                .foregroundColor(statusColor(for: gameState.status))
                        }
                    }
                    
                    if let trigger = gameState.trigger, !trigger.isEmpty {
                        Text("Last Trigger: \(trigger)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(8)
                            .background(.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            } else {
                Text("No active game")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var gameFlowCard: some View {
        VStack(spacing: 16) {
            Text("Game Flow")
                .font(.headline)
            
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Button("Start Game") {
                        Task {
                            // First start the game in HostedEventManager
                            let result = await hostedEventManager.startGame()
                            switch result {
                            case .success:
                                print("✅ Game started successfully")

                                // Load the trivia game from Firebase
                                if let gameId = hostedEventManager.currentEvent?.gameConfig?.triviaGameId {
                                    print("📚 Loading trivia game: \(gameId)")
                                    await triviaGameManager.loadTriviaGame(gameId)
                                } else {
                                    print("⚠️ No trivia game ID found in event config")
                                }

                            case .failure(let error):
                                print("❌ Failed to start game: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(hostedEventManager.gameState?.status == .question_active)
                    
                    Button("End Game") {
                        Task {
                            let result = await hostedEventManager.endGame()
                            switch result {
                            case .success:
                                print("✅ Game ended successfully")
                            case .failure(let error):
                                print("❌ Failed to end game: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                Divider()
                
                HStack(spacing: 16) {
                    Button("Next Round") {
                        Task {
                            let result = await hostedEventManager.nextRound()
                            switch result {
                            case .success:
                                print("✅ Advanced to next round")
                            case .failure(let error):
                                print("❌ Failed to advance round: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Next Question") {
                        Task {
                            // First advance the question in game state
                            let result = await hostedEventManager.nextQuestion()
                            switch result {
                            case .success:
                                print("✅ Advanced to next question in game state")

                                // Now load the actual question from TriviaGameManager
                                if let game = triviaGameManager.currentGame,
                                   let gameState = hostedEventManager.gameState,
                                   let questionNum = gameState.currentQuestion {

                                    // Get the question from the current round
                                    let allQuestions = game.rounds.flatMap { $0.questions }
                                    if questionNum > 0 && questionNum <= allQuestions.count {
                                        let question = allQuestions[questionNum - 1]
                                        await triviaGameManager.startQuestion(question.id)
                                        print("📝 Started question: \(question.questionText)")
                                    }
                                }

                            case .failure(let error):
                                print("❌ Failed to advance question: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(triviaGameManager.currentGame == nil)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var timerControlCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Question Timer")
                    .font(.headline)

                Spacer()

                // Timer display
                Text(formatTime(remainingSeconds))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundColor(timerColor)
            }

            // Timer preset buttons
            VStack(spacing: 12) {
                Text("Quick Timers")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ForEach([15, 30, 60, 90, 120], id: \.self) { seconds in
                        Button("\(seconds)s") {
                            timerSeconds = seconds
                            remainingSeconds = seconds
                        }
                        .buttonStyle(.bordered)
                        .tint(timerSeconds == seconds ? .blue : .gray)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            // Timer controls
            HStack(spacing: 12) {
                Button {
                    startTimer()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(timerRunning)

                Button {
                    pauseTimer()
                } label: {
                    HStack {
                        Image(systemName: "pause.fill")
                        Text("Pause")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!timerRunning)

                Button {
                    resetTimer()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    addTime(15)
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("+15s")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.purple)
            }

            // Progress bar
            ProgressView(value: Double(remainingSeconds), total: Double(timerSeconds))
                .progressViewStyle(LinearProgressViewStyle(tint: timerColor))
                .scaleEffect(y: 2)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var timerColor: Color {
        if !timerRunning {
            return .blue
        } else if remainingSeconds > 10 {
            return .green
        } else if remainingSeconds > 5 {
            return .orange
        } else {
            return .red
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func startTimer() {
        guard !timerRunning else { return }

        timerRunning = true

        // Broadcast timer start to all participants
        Task {
            await hostedEventManager.triggerNotification("timer_start_\(remainingSeconds)")
        }

        timerTask = Task {
            while remainingSeconds > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))

                await MainActor.run {
                    if remainingSeconds > 0 {
                        remainingSeconds -= 1

                        // Alert when time is running out
                        if remainingSeconds == 10 {
                            Task {
                                await hostedEventManager.triggerNotification("timer_warning_10")
                            }
                        } else if remainingSeconds == 0 {
                            Task {
                                await hostedEventManager.triggerNotification("timer_expired")
                            }
                            timerRunning = false
                        }
                    }
                }
            }

            await MainActor.run {
                timerRunning = false
            }
        }
    }

    private func pauseTimer() {
        timerRunning = false
        timerTask?.cancel()
        timerTask = nil

        Task {
            await hostedEventManager.triggerNotification("timer_paused")
        }
    }

    private func resetTimer() {
        timerRunning = false
        timerTask?.cancel()
        timerTask = nil
        remainingSeconds = timerSeconds

        Task {
            await hostedEventManager.triggerNotification("timer_reset")
        }
    }

    private func addTime(_ seconds: Int) {
        remainingSeconds += seconds

        Task {
            await hostedEventManager.triggerNotification("timer_add_\(seconds)")
        }
    }

    private var submissionTrackingCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Answer Submissions")
                    .font(.headline)

                Spacer()

                let submissionCount = hostedEventManager.gameState?.submissions?.count ?? 0
                let totalTables = hostedEventManager.tables.count

                Text("\(submissionCount)/\(totalTables)")
                    .font(.title3.bold())
                    .foregroundColor(submissionCount == totalTables ? .green : .orange)
            }

            if hostedEventManager.tables.isEmpty {
                Text("No tables available")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(hostedEventManager.tables.sorted(by: { $0.tableNumber < $1.tableNumber }), id: \.tableNumber) { table in
                        SubmissionStatusCard(
                            table: table,
                            submission: hostedEventManager.getSubmissionStatus(for: table.tableNumber)
                        )
                    }
                }

                Divider()

                // Clear submissions button
                Button {
                    Task {
                        let result = await hostedEventManager.clearSubmissions()
                        switch result {
                        case .success:
                            print("✅ Cleared all submissions")
                        case .failure(let error):
                            print("❌ Failed to clear submissions: \(error)")
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Clear All Submissions")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled((hostedEventManager.gameState?.submissions?.isEmpty ?? true))
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var scoringCard: some View {
        VStack(spacing: 16) {
            Text("Table Scoring & Effects")
                .font(.headline)

            Text("Award/deduct points and trigger animations for tables")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(hostedEventManager.tables, id: \.tableNumber) { table in
                        TableControlCard(
                            table: table,
                            currentScore: hostedEventManager.gameState?.scores["\(table.tableNumber)"] ?? 0,
                            onAwardPoints: { points in
                                Task { await hostedEventManager.awardPoints(to: table.tableNumber, points: points) }
                            },
                            onTriggerAnimation: { animation in
                                Task { await triggerTableAnimation(table: table.tableNumber, animation: animation) }
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    // MARK: - Table Animation Helper

    private func triggerTableAnimation(table: Int, animation: TableAnimation) async {
        print("🎬 [Host] Triggering \(animation.rawValue) for table \(table)...")

        if let immersiveAnimation = TableAnimationType(rawValue: animation.rawValue) {
            await MainActor.run {
                triviaImmersiveManager.triggerAnimationManually(
                    tableNumber: table,
                    animation: immersiveAnimation
                )
            }
        }

        await hostedEventManager.triggerNotification("table_\(table)_\(animation.rawValue)")

        print("✅ [Host] Animation trigger completed for table \(table)")
    }
    
    // MARK: - Participants Tab
    
    private var participantManagementTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Participant Management")
                    .font(.largeTitle.bold())
                    .padding(.top)
                
                participantOverviewCard
                tableAssignmentCard
                
                Spacer()
            }
            .padding()
        }
    }
    
    private var participantOverviewCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Participants")
                    .font(.headline)
                Spacer()
                Text("\(hostedEventManager.participants.count) total")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if hostedEventManager.participants.isEmpty {
                Text("No participants yet")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(hostedEventManager.participants) { participant in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(participant.userName)
                                .font(.body)
                                .fontWeight(.medium)
                            
                            if let tableNumber = participant.tableNumber {
                                Text("Table \(tableNumber)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            } else {
                                Text("Unassigned")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            
                            Text("Role: \(participant.role.rawValue.capitalized)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.gray.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var tableAssignmentCard: some View {
        VStack(spacing: 16) {
            Text("Table Overview")
                .font(.headline)
            
            if hostedEventManager.tables.isEmpty {
                Text("No tables configured")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(hostedEventManager.tables, id: \.tableNumber) { table in
                        VStack(spacing: 8) {
                            Text(table.teamName ?? "Table \(table.tableNumber)")
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Text("\(table.participants.count)/\(table.maxSeats)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ProgressView(value: Float(table.participants.count), total: Float(table.maxSeats))
                                .progressViewStyle(LinearProgressViewStyle(tint: table.isFull ? .red : .blue))
                            
                            if table.isFull {
                                Text("FULL")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(12)
                        .background(.gray.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Broadcast Tab
    
    private var broadcastTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Broadcast Controls")
                    .font(.largeTitle.bold())
                    .padding(.top)
                
                broadcastActionsCard
                customMessageCard
                
                Spacer()
            }
            .padding()
        }
    }
    
    private var broadcastActionsCard: some View {
        VStack(spacing: 16) {
            Text("Quick Actions")
                .font(.headline)
            
            Text("Send pre-defined notifications to all participants")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(hostedEventManager.notificationActions, id: \.self) { action in
                    Button(action) {
                        Task {
                            await hostedEventManager.triggerNotification(action)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            
            if let lastTrigger = hostedEventManager.gameState?.trigger, !lastTrigger.isEmpty {
                Text("Last sent: \(lastTrigger)")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    @State private var customMessage = ""
    
    private var customMessageCard: some View {
        VStack(spacing: 16) {
            Text("Custom Message")
                .font(.headline)
            
            TextField("Enter custom announcement...", text: $customMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            
            Button("Send Custom Message") {
                guard !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                
                Task {
                    await hostedEventManager.triggerNotification(customMessage)
                    customMessage = ""
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    private func statusColor(for status: GameStatus) -> Color {
        switch status {
        case .waiting:
            return .orange
        case .question_active:
            return .green
        case .finished:
            return .red
        }
    }
}

// MARK: - Table Animation Types

enum TableAnimation: String, CaseIterable {
    case correctAnswer = "correct_answer"
    case wrongAnswer = "wrong_answer"
    case celebrate = "celebrate"
    case thinking = "thinking"
    case timeWarning = "time_warning"
    case bounce = "bounce"
    case shake = "shake"
    case glow = "glow"
    case pulse = "pulse"

    var icon: String {
        switch self {
        case .correctAnswer: return "checkmark.circle.fill"
        case .wrongAnswer: return "xmark.circle.fill"
        case .celebrate: return "party.popper.fill"
        case .thinking: return "brain.head.profile"
        case .timeWarning: return "clock.badge.exclamationmark"
        case .bounce: return "arrow.up.and.down"
        case .shake: return "waveform"
        case .glow: return "sparkles"
        case .pulse: return "waveform.path.ecg"
        }
    }

    var displayName: String {
        switch self {
        case .correctAnswer: return "Correct"
        case .wrongAnswer: return "Wrong"
        case .celebrate: return "Celebrate"
        case .thinking: return "Thinking"
        case .timeWarning: return "Hurry Up!"
        case .bounce: return "Bounce"
        case .shake: return "Shake"
        case .glow: return "Glow"
        case .pulse: return "Pulse"
        }
    }

    var color: Color {
        switch self {
        case .correctAnswer: return .green
        case .wrongAnswer: return .red
        case .celebrate: return .yellow
        case .thinking: return .blue
        case .timeWarning: return .orange
        case .bounce, .shake, .pulse: return .purple
        case .glow: return .cyan
        }
    }
}

// MARK: - Submission Status Card

struct SubmissionStatusCard: View {
    let table: EventTable
    let submission: AnswerSubmission?

    var hasSubmitted: Bool {
        submission?.locked ?? false
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if hasSubmitted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(table.teamName ?? "Table \(table.tableNumber)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let submittedAt = submission?.submittedAt {
                        Text(submittedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Waiting...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(hasSubmitted ? .green.opacity(0.1) : .gray.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(hasSubmitted ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Table Control Card

struct TableControlCard: View {
    let table: EventTable
    let currentScore: Int
    let onAwardPoints: (Int) -> Void
    let onTriggerAnimation: (TableAnimation) -> Void

    @State private var showAnimations = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            VStack(spacing: 4) {
                Text(table.teamName ?? "Table \(table.tableNumber)")
                    .font(.headline)
                    .lineLimit(1)

                Text("\(currentScore) points")
                    .font(.title2.bold())
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.1))
            .cornerRadius(8)

            // Point Controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Points")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button("-10") {
                        onAwardPoints(-10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)

                    Button("-5") {
                        onAwardPoints(-5)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)

                    Spacer()

                    Button("+5") {
                        onAwardPoints(5)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("+10") {
                        onAwardPoints(10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Divider()

            // Animation Controls
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Animations")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(showAnimations ? "Hide" : "Show") {
                        withAnimation {
                            showAnimations.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(.blue)
                }

                if showAnimations {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 6) {
                        ForEach(TableAnimation.allCases, id: \.self) { animation in
                            Button {
                                onTriggerAnimation(animation)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: animation.icon)
                                        .font(.caption2)
                                    Text(animation.displayName)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(animation.color)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Preview

#if DEBUG
struct TriviaHostControlsView_Previews: PreviewProvider {
    static var previews: some View {
        TriviaHostControlsView()
            .environmentObject(HostedEventManager.shared)
            .environmentObject(TriviaGameManager.shared)
            .environmentObject(PersonaTableManager())
            .environmentObject(TriviaImmersiveManager())
    }
}
#endif
