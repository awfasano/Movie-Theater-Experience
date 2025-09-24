//
//  ShareplayTestView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/23/25.
//

import Foundation

//
//  SharePlayTestView.swift
//  Movie Theater Experience
//
//  Debug and testing interface for SharePlay functionality
//

import SwiftUI

struct SharePlayTestView: View {
    @EnvironmentObject private var triviaSharePlayManager: TriviaSharePlayManager
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @State private var testMessage = ""
    @State private var selectedTableNumber = 1
    @State private var selectedAnswer = 0
    @State private var logMessages: [String] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    connectionStatusSection
                    participantsSection
                    testActionsSection
                    logSection
                }
                .padding()
            }
            .navigationTitle("SharePlay Debug")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                setupLogging()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "shareplay")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("SharePlay Test Console")
                .font(.title2.bold())
            
            Text("Test and debug SharePlay functionality for trivia events")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Connection Status
    
    private var connectionStatusSection: some View {
        VStack(spacing: 16) {
            Text("Connection Status")
                .font(.headline)
            
            VStack(spacing: 12) {
                statusRow(title: "SharePlay Session",
                         value: triviaSharePlayManager.isSessionActive ? "Active" : "Inactive",
                         color: triviaSharePlayManager.isSessionActive ? .green : .red)
                
                statusRow(title: "Hosted Event Manager",
                         value: hostedEventManager.sharePlayActive ? "Active" : "Inactive",
                         color: hostedEventManager.sharePlayActive ? .green : .red)
                
                statusRow(title: "Participants",
                         value: "\(triviaSharePlayManager.participants.count)",
                         color: .blue)
                
                statusRow(title: "Current Event",
                         value: hostedEventManager.currentEvent?.title ?? "None",
                         color: hostedEventManager.currentEvent != nil ? .green : .orange)
            }
            .padding()
            .background(.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func statusRow(title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.body.bold())
                .foregroundColor(color)
        }
    }
    
    // MARK: - Participants Section
    
    private var participantsSection: some View {
        VStack(spacing: 16) {
            Text("Participants")
                .font(.headline)
            
            if triviaSharePlayManager.participants.isEmpty {
                Text("No participants connected")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.gray.opacity(0.1))
                    .cornerRadius(8)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(Array(triviaSharePlayManager.participants), id: \.id) { participant in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 12, height: 12)
                            
                            Text("Participant")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text(participant.id.uuidString.prefix(8))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospaced()
                        }
                        .padding()
                        .background(.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - Test Actions Section
    
    private var testActionsSection: some View {
        VStack(spacing: 20) {
            Text("Test Actions")
                .font(.headline)
            
            // Session Controls
            sessionControlsCard
            
            // Message Testing
            messageTestingCard
            
            // Host Controls Testing
            hostControlsCard
        }
    }
    
    private var sessionControlsCard: some View {
        VStack(spacing: 12) {
            Text("Session Controls")
                .font(.subheadline.bold())
            
            HStack(spacing: 16) {
                Button("Start Session") {
                    Task {
                        await startTestSession()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(triviaSharePlayManager.isSessionActive)
                
                Button("End Session") {
                    triviaSharePlayManager.endSession()
                    addLog("Session ended manually")
                }
                .buttonStyle(.bordered)
                .disabled(!triviaSharePlayManager.isSessionActive)
            }
        }
        .padding()
        .background(.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var messageTestingCard: some View {
        VStack(spacing: 16) {
            Text("Message Testing")
                .font(.subheadline.bold())
            
            // Vote Testing
            VStack(spacing: 8) {
                Text("Test Vote Message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Picker("Table", selection: $selectedTableNumber) {
                        ForEach(1...4, id: \.self) { table in
                            Text("Table \(table)").tag(table)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 120)
                    
                    Picker("Answer", selection: $selectedAnswer) {
                        ForEach(0...3, id: \.self) { answer in
                            Text("\(answer + 1)").tag(answer)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 120)
                }
                
                Button("Send Vote") {
                    Task {
                        await sendTestVote()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!triviaSharePlayManager.isSessionActive)
            }
            
            Divider()
            
            // Custom Message Testing
            VStack(spacing: 8) {
                Text("Custom Message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Enter test message...", text: $testMessage)
                    .textFieldStyle(.roundedBorder)
                
                Button("Send Custom Notification") {
                    Task {
                        await sendTestNotification()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!triviaSharePlayManager.isSessionActive || testMessage.isEmpty)
            }
        }
        .padding()
        .background(.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var hostControlsCard: some View {
        VStack(spacing: 12) {
            Text("Host Controls Testing")
                .font(.subheadline.bold())
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                Button("Start Game") {
                    Task {
                        let result = await hostedEventManager.startGame()
                        addLog("Start game result: \(result)")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Next Round") {
                    Task {
                        let result = await hostedEventManager.nextRound()
                        addLog("Next round result: \(result)")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Award Points") {
                    Task {
                        let result = await hostedEventManager.awardPoints(to: selectedTableNumber, points: 10)
                        addLog("Award points result: \(result)")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("End Game") {
                    Task {
                        let result = await hostedEventManager.endGame()
                        addLog("End game result: \(result)")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Log Section
    
    private var logSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Debug Log")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear") {
                    logMessages.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(logMessages.enumerated()), id: \.offset) { index, message in
                        HStack(alignment: .top) {
                            Text("\(index + 1).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 30, alignment: .trailing)
                            
                            Text(message)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding()
            }
            .frame(height: 200)
            .background(.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Test Actions
    
    private func startTestSession() async {
        addLog("Attempting to start SharePlay session...")
        
        // Create a test event if none exists
        if hostedEventManager.currentEvent == nil {
            addLog("No current event - this would normally require joining an event first")
            return
        }
        
        let success = await hostedEventManager.startSharePlaySession()
        addLog("SharePlay session start result: \(success)")
    }
    
    private func sendTestVote() async {
        addLog("Sending test vote: Table \(selectedTableNumber), Answer \(selectedAnswer + 1)")
        
        await triviaSharePlayManager.sendVote(
            userId: AppModel.shared.currentUserId,
            userName: AppModel.shared.username.isEmpty ? "Test User" : AppModel.shared.username,
            tableNumber: selectedTableNumber,
            answer: selectedAnswer
        )
        
        addLog("Test vote sent successfully")
    }
    
    private func sendTestNotification() async {
        addLog("Sending test notification: \(testMessage)")
        
        guard let eventId = hostedEventManager.currentEvent?.id else {
            addLog("Error: No current event ID")
            return
        }
        
        await triviaSharePlayManager.sendHostNotification(
            testMessage,
            type: "test",
            eventId: eventId
        )
        
        addLog("Test notification sent successfully")
        testMessage = ""
    }
    
    // MARK: - Logging
    
    private func setupLogging() {
        addLog("SharePlay Debug Console initialized")
        addLog("User ID: \(AppModel.shared.currentUserId)")
        addLog("Username: \(AppModel.shared.username)")
        
        // Listen for SharePlay events
        NotificationCenter.default.addObserver(
            forName: .sharePlayVoteReceived,
            object: nil,
            queue: .main
        ) { notification in
            if let vote = notification.object as? VoteMessage {
                addLog("📥 Received vote: \(vote.userName) -> \(vote.answer) at table \(vote.tableNumber)")
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .sharePlayHostNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let notification = notification.object as? HostNotification {
                addLog("📢 Received notification: \(notification.message)")
            }
        }
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.append("[\(timestamp)] \(message)")
        
        // Keep only last 50 messages
        if logMessages.count > 50 {
            logMessages.removeFirst(logMessages.count - 50)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SharePlayTestView_Previews: PreviewProvider {
    static var previews: some View {
        SharePlayTestView()
            .environmentObject(TriviaSharePlayManager.shared)
            .environmentObject(HostedEventManager.shared)
    }
}
#endif
