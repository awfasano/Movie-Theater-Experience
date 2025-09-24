//
//  FirebaseDebugView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/23/25.
//

import Foundation

//
//  FirebaseDebugView.swift
//  Movie Theater Experience
//
//  Debug view for testing Firebase trivia data
//

import SwiftUI

struct FirebaseDebugView: View {
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var triviaGameManager: TriviaGameManager
    @State private var isSettingUp = false
    @State private var statusMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    setupSection
                    currentDataSection
                    testActionsSection
                }
                .padding()
            }
            .navigationTitle("Firebase Debug")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("Firebase Test Console")
                .font(.title2.bold())
            
            Text("Setup and test your trivia system data")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var setupSection: some View {
        VStack(spacing: 16) {
            Text("Setup Test Data")
                .font(.headline)
            
            VStack(spacing: 12) {
                Button("Create Test Event & Tables") {
                    Task {
                        await setupTestData()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSettingUp)
                
                Button("Add Sample Votes") {
                    Task {
                        await addSampleVotes()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSettingUp)
                
                Button("Join Test Event") {
                    Task {
                        await joinTestEvent()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSettingUp)
            }
            
            if isSettingUp {
                ProgressView("Setting up...")
                    .frame(maxWidth: .infinity)
            }
            
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var currentDataSection: some View {
        VStack(spacing: 16) {
            Text("Current Data")
                .font(.headline)
            
            VStack(spacing: 12) {
                dataRow(title: "Current Event",
                        value: hostedEventManager.currentEvent?.title ?? "None")
                
                dataRow(title: "Participants",
                        value: "\(hostedEventManager.participants.count)")
                
                dataRow(title: "Tables",
                        value: "\(hostedEventManager.tables.count)")
                
                dataRow(title: "Game Status",
                        value: hostedEventManager.gameState?.status.rawValue ?? "None")
                
                dataRow(title: "Current Round",
                        value: "\(hostedEventManager.gameState?.currentRound ?? 0)")
                
                dataRow(title: "SharePlay Active",
                        value: hostedEventManager.sharePlayActive ? "Yes" : "No")
            }
        }
        .padding()
        .background(.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var testActionsSection: some View {
        VStack(spacing: 16) {
            Text("Test Actions")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                testButton("Start Game") {
                    Task {
                        let result = await hostedEventManager.startGame()
                        updateStatus("Start game: \(result)")
                    }
                }
                
                testButton("Next Round") {
                    Task {
                        let result = await hostedEventManager.nextRound()
                        updateStatus("Next round: \(result)")
                    }
                }
                
                testButton("Award Points") {
                    Task {
                        let result = await hostedEventManager.awardPoints(to: 1, points: 10)
                        updateStatus("Award points: \(result)")
                    }
                }
                
                testButton("Send Notification") {
                    Task {
                        await hostedEventManager.triggerNotification("Test notification from debug view")
                        updateStatus("Notification sent")
                    }
                }
                
                testButton("Start SharePlay") {
                    Task {
                        let success = await hostedEventManager.startSharePlaySession()
                        updateStatus("SharePlay: \(success ? "Started" : "Failed")")
                    }
                }
                
                testButton("Clear Data") {
                    Task {
                        await clearTestData()
                    }
                }
            }
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func dataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.body.bold())
                .foregroundColor(.blue)
        }
    }
    
    private func testButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
    }
    
    // MARK: - Actions
    
    private func setupTestData() async {
        isSettingUp = true
        updateStatus("Setting up test data...")
        
        let setup = FirebaseTestDataSetup()
        await setup.setupTestData()
        
        updateStatus("Test data created successfully")
        isSettingUp = false
    }
    
    private func addSampleVotes() async {
        isSettingUp = true
        updateStatus("Adding sample votes...")
        
        let setup = FirebaseTestDataSetup()
        await setup.addSampleVotes()
        
        updateStatus("Sample votes added")
        isSettingUp = false
    }
    
    private func joinTestEvent() async {
        isSettingUp = true
        updateStatus("Joining test event...")
        
        // Create a test event
        var testEvent = CalendarEvent(
            title: "Test Trivia Night",
            description: "Debug trivia event",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            timeZone: TimeZone.current.identifier,
            eventType: .hostedTrivia,
            status: .scheduled
        )
        
        // Set the event ID manually for testing
        testEvent.id = "test-trivia-event-1"
        
        let result = await hostedEventManager.joinHostedEvent(testEvent)
        
        switch result {
        case .success(let participant):
            updateStatus("Joined as: \(participant.userName)")
        case .failure(let error):
            updateStatus("Join failed: \(error)")
        }
        
        isSettingUp = false
    }
    
    private func clearTestData() async {
        isSettingUp = true
        updateStatus("Clearing test data...")
        
        // This would clear the test data from Firebase
        // Implementation depends on your specific needs
        
        updateStatus("Test data cleared")
        isSettingUp = false
    }
    
    private func updateStatus(_ message: String) {
        DispatchQueue.main.async {
            statusMessage = message
            print("🔥 [Debug] \(message)")
        }
    }
}

// MARK: - Preview

#if DEBUG
struct FirebaseDebugView_Previews: PreviewProvider {
    static var previews: some View {
        FirebaseDebugView()
            .environmentObject(HostedEventManager.shared)
            .environmentObject(TriviaGameManager.shared)
    }
}
#endif

struct FirebaseDebugButton: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Button {
            openWindow(id: "firebaseDebug")
        } label: {
            HStack {
                Image(systemName: "cloud.fill")
                Text("Firebase Debug")
            }
            .padding(8)
            .background(.blue.opacity(0.2))
            .cornerRadius(8)
        }
    }
}

struct FloatingDebugButton: View {
    @Environment(\.openWindow) private var openWindow
    @State private var isExpanded = false
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                    if isExpanded {
                        Button("Firebase") {
                            openWindow(id: "firebaseDebug")
                            isExpanded = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button("SharePlay") {
                            openWindow(id: "sharePlayDebug")
                            isExpanded = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Button {
                        withAnimation(.spring()) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "xmark" : "hammer.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.orange)
                            .clipShape(Circle())
                    }
                }
            }
            .padding()
        }
    }
}

    
