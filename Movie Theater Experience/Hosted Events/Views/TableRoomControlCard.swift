//
//  TableRoomControlCard.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/26/25.
//

import Foundation

//
//  TableRoomControlCard.swift
//  Movie Theater Experience
//
//  Individual table voice chat control card for the host

import SwiftUI

struct TableRoomControlCard: View {
    let table: EventTable
    let onJoinVoiceChat: () -> Void
    
    @StateObject private var hostAudioManager = HostAudioManager.shared
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @State private var isConnected = false
    @State private var roomCode: String = ""
    
    var body: some View {
        VStack(spacing: 12) {
            // Table Header Info
            VStack(spacing: 4) {
                Text(table.teamName ?? "Table \(table.tableNumber)")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    // Participant count
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption)
                        Text("\(table.participants.count)/\(table.maxSeats)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    // Current score
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                        Text("\(getCurrentScore()) pts")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                }
            }
            
            // Room Code Display
            VStack(spacing: 4) {
                Text("Room Code")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(roomCode.isEmpty ? "------" : roomCode)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(roomCode.isEmpty ? .secondary : .blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(6)
            }
            
            // Connection Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 8, height: 8)
                
                Text(connectionStatusText)
                    .font(.caption)
                    .foregroundColor(connectionStatusColor)
                    .fontWeight(.medium)
            }
            
            // Voice Chat Controls
            VStack(spacing: 8) {
                if !isConnected {
                    Button("Connect Voice Chat") {
                        connectToVoiceChat()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(table.participants.isEmpty)
                } else {
                    HStack(spacing: 8) {
                        Button("Listen") {
                            onJoinVoiceChat()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Leave") {
                            disconnectFromVoiceChat()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                    }
                }
                
                // Quick Actions
                if isConnected {
                    HStack(spacing: 4) {
                        Button {
                            muteTable()
                        } label: {
                            Image(systemName: "speaker.slash")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        Button {
                            broadcastToTable("Great job, team!")
                        } label: {
                            Image(systemName: "megaphone")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        Button {
                            checkOnTable()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(16)
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .background(backgroundStyle)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .cornerRadius(12)
        .onAppear {
            setupRoomCode()
            checkConnectionStatus()
        }
        .onChange(of: hostAudioManager.currentConnectedRoom) { _, newRoom in
            isConnected = (newRoom == roomCode)
        }
    }
    
    // MARK: - Computed Properties
    
    private var connectionStatusColor: Color {
        if isConnected {
            return .green
        } else if table.participants.isEmpty {
            return .gray
        } else {
            return .orange
        }
    }
    
    private var connectionStatusText: String {
        if isConnected {
            return "Connected"
        } else if table.participants.isEmpty {
            return "No Players"
        } else {
            return "Ready to Connect"
        }
    }
    
    private var backgroundStyle: some ShapeStyle {
        if isConnected {
            return Color.green.opacity(0.05)
        } else if hostAudioManager.currentConnectedRoom == roomCode {
            return Color.blue.opacity(0.1)
        } else {
            return Color.gray.opacity(0.02)
        }
    }
    
    private var borderColor: Color {
        if isConnected {
            return .green
        } else if hostAudioManager.currentConnectedRoom == roomCode {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }
    
    private var borderWidth: CGFloat {
        isConnected ? 2 : 1
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentScore() -> Int {
        return hostedEventManager.gameState?.scores["\(table.tableNumber)"] ?? 0
    }
    
    private func setupRoomCode() {
        // Generate consistent room code for this table
        roomCode = "TBL\(String(format: "%02d", table.tableNumber))"
        
        // Register this room with the host audio manager
        hostAudioManager.registerRoom(
            roomCode: roomCode,
            tableNumber: table.tableNumber,
            teamName: table.teamName
        )
    }
    
    private func checkConnectionStatus() {
        if let roomStatus = hostAudioManager.getRoomStatus(for: table.tableNumber) {
            isConnected = roomStatus.isConnected
        }
    }
    
    // MARK: - Actions
    
    private func connectToVoiceChat() {
        print("🎤 [Host] Connecting to Table \(table.tableNumber) voice chat")
        
        // Create room code for participants to join
        Task {
            await createTableVoiceChatRoom()
        }
        
        isConnected = true
    }
    
    private func disconnectFromVoiceChat() {
        print("🚪 [Host] Disconnecting from Table \(table.tableNumber)")
        
        hostAudioManager.leaveRoom(roomCode)
        isConnected = false
    }
    
    private func muteTable() {
        print("🔇 [Host] Muting Table \(table.tableNumber)")
        // Implementation would mute audio from this specific table
    }
    
    private func broadcastToTable(_ message: String) {
        print("📢 [Host] Broadcasting to Table \(table.tableNumber): \(message)")
        
        Task {
            // Send notification specifically to this table
            await hostedEventManager.triggerNotification("Host to Table \(table.tableNumber): \(message)")
        }
    }
    
    private func checkOnTable() {
        print("❓ [Host] Checking on Table \(table.tableNumber)")
        
        Task {
            await broadcastToTable("How are you doing? Need any help?")
        }
    }
    
    private func createTableVoiceChatRoom() async {
        // Store room information in Firebase so participants can find it
        guard let eventId = hostedEventManager.currentEvent?.id else { return }
        
        do {
            let db = Firestore.firestore(database: "uploads")
            
            let roomData: [String: Any] = [
                "roomCode": roomCode,
                "tableNumber": table.tableNumber,
                "eventId": eventId,
                "teamName": table.teamName ?? "Table \(table.tableNumber)",
                "hostId": AppModel.shared.currentUserId,
                "isActive": true,
                "createdAt": Date(),
                "participantCount": table.participants.count,
                "maxParticipants": table.maxSeats
            ]
            
            try await db.collection("TableVoiceRooms")
                .document(roomCode)
                .setData(roomData)
            
            print("✅ [Host] Created voice chat room for Table \(table.tableNumber): \(roomCode)")
            
        } catch {
            print("❌ [Host] Failed to create voice chat room: \(error)")
        }
    }
}
