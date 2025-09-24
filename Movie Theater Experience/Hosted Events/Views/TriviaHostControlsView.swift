//
//  Enhanced TriviaHostControlsView.swift
//  Movie Theater Experience
//
//  Host controls with SharePlay integration
//

import SwiftUI

struct TriviaHostControlsView: View {
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var triviaGameManager: TriviaGameManager
    @EnvironmentObject private var personaManager: PersonaTableManager
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            
            sharePlayControlsTab
                .tabItem {
                    Label("SharePlay", systemImage: "shareplay")
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
    
    // MARK: - SharePlay Controls Tab
    
    private var sharePlayControlsTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("SharePlay Controls")
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
                    .fill(hostedEventManager.sharePlayActive ? .green : .red)
                    .frame(width: 16, height: 16)
                
                Text(hostedEventManager.sharePlayActive ? "SharePlay Active" : "SharePlay Inactive")
                    .font(.title2.bold())
                    .foregroundColor(hostedEventManager.sharePlayActive ? .green : .red)
                
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Participants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(TriviaSharePlayManager.shared.participants.count)")
                        .font(.title3.bold())
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Session ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(hostedEventManager.sharePlayActive ? "Connected" : "None")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var sessionControlsCard: some View {
        VStack(spacing: 16) {
            Text("Session Management")
                .font(.headline)
            
            if !hostedEventManager.sharePlayActive {
                Button(action: {
                    Task {
                        let success = await hostedEventManager.startSharePlaySession()
                        print(success ? "✅ SharePlay started" : "❌ SharePlay failed")
                    }
                }) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("Start SharePlay Session")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green)
                    .cornerRadius(10)
                }
                
                Text("Start a SharePlay session to enable real-time synchronization with participants")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
            } else {
                Button(action: {
                    hostedEventManager.endSharePlaySession()
                }) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("End SharePlay Session")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.red)
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var participantsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SharePlay Participants")
                .font(.headline)
            
            if TriviaSharePlayManager.shared.participants.isEmpty {
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
                    ForEach(Array(TriviaSharePlayManager.shared.participants), id: \.id) { participant in
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            
                            Text("Participant \(participant.id.uuidString.prefix(8))")
                                .font(.caption)
                                .lineLimit(1)
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
            Text("Live Notifications")
                .font(.headline)
            
            if hostedEventManager.liveNotifications.isEmpty {
                Text("No active notifications")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                
            } else {
                ForEach(hostedEventManager.liveNotifications, id: \.message) { notification in
                    HStack {
                        Image(systemName: "megaphone.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notification.message)
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Text(notification.type.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(notification.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
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
                
                // Game Flow Controls
                gameFlowCard
                
                // Scoring Controls
                scoringCard
                
                Spacer()
            }
            .padding()
        }
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
                            let result = await hostedEventManager.startGame()
                            switch result {
                            case .success:
                                print("✅ Game started successfully")
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
                            let result = await hostedEventManager.nextQuestion()
                            switch result {
                            case .success:
                                print("✅ Advanced to next question")
                            case .failure(let error):
                                print("❌ Failed to advance question: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private var scoringCard: some View {
        VStack(spacing: 16) {
            Text("Quick Scoring")
                .font(.headline)
            
            Text("Award points to tables for correct answers")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(hostedEventManager.tables, id: \.tableNumber) { table in
                    VStack(spacing: 8) {
                        Text(table.teamName ?? "Table \(table.tableNumber)")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        let currentScore = hostedEventManager.gameState?.scores["\(table.tableNumber)"] ?? 0
                        Text("\(currentScore) pts")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Button("+5") {
                                Task { await hostedEventManager.awardPoints(to: table.tableNumber, points: 5) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            
                            Button("+10") {
                                Task { await hostedEventManager.awardPoints(to: table.tableNumber, points: 10) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                    }
                    .padding(8)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
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

// MARK: - Preview

#if DEBUG
struct TriviaHostControlsView_Previews: PreviewProvider {
    static var previews: some View {
        TriviaHostControlsView()
            .environmentObject(HostedEventManager.shared)
            .environmentObject(TriviaGameManager.shared)
            .environmentObject(PersonaTableManager())
    }
}
#endif
