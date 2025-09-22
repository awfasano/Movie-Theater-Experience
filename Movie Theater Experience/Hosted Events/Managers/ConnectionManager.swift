//
//  ConnectionManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/17/25.
//

import Foundation
import SwiftUI
import FirebaseFirestoreInternalWrapper
import FirebaseFirestore

// Managers/ConnectionManager.swift
class ConnectionManager: ObservableObject {
    @Published var connectionState: ConnectionState = .connected
    @Published var reconnectAttempts = 0
    private var reconnectTimer: Timer?
    private let maxReconnectAttempts = 5
    
    enum ConnectionState {
        case connected
        case disconnected
        case reconnecting
        case failed
    }
    
    func handleDisconnection() {
        connectionState = .reconnecting
        reconnectAttempts = 0
        startReconnection()
    }
    
    private func startReconnection() {
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await self.attemptReconnection()
            }
        }
    }
    
    @MainActor
    private func attemptReconnection() async {
        reconnectAttempts += 1
        
        if reconnectAttempts > maxReconnectAttempts {
            connectionState = .failed
            reconnectTimer?.invalidate()
            return
        }
        
        // Try to reconnect to Firebase
        if await testConnection() {
            connectionState = .connected
            reconnectTimer?.invalidate()
            await resyncGameState()
        }
    }
    
    private func testConnection() async -> Bool {
        // Test Firebase connection by attempting to fetch a single document
        do {
            let db = Firestore.firestore()
            let query = db.collection("Events").limit(to: 1)
            _ = try await query.getDocuments()
            return true
        } catch {
            return false
        }
    }
    
    private func resyncGameState() async {
        // Re-fetch current game state
        // Re-subscribe to listeners
        // Update local state
    }
}

// Error recovery UI
struct ConnectionStatusView: View {
    @ObservedObject var connectionManager: ConnectionManager
    
    var body: some View {
        if connectionManager.connectionState != .connected {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text(statusText)
                    .font(.caption)
                
                if connectionManager.connectionState == .failed {
                    Button("Retry") {
                        connectionManager.handleDisconnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(.red.opacity(0.2))
            .cornerRadius(8)
        }
    }
    
    var statusText: String {
        switch connectionManager.connectionState {
        case .disconnected:
            return "Connection lost"
        case .reconnecting:
            return "Reconnecting... (\(connectionManager.reconnectAttempts)/5)"
        case .failed:
            return "Connection failed"
        case .connected:
            return ""
        }
    }
}

