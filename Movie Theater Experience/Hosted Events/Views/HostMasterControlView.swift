//
//  HostMasterControlView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/27/25.
//

import Foundation

//
//  HostMasterControlView.swift
//  Movie Theater Experience
//
//  Main host dashboard for audio control and room management

import SwiftUI
import AVFoundation

struct HostMasterControlView: View {
    @StateObject private var hostAudioManager = HostAudioManager.shared
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @Environment(\.openWindow) private var openWindow
    @State private var showingQuickCommPanel = false
    @State private var showingBroadcastAlert = false
    @State private var broadcastMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                broadcastControlsSection
                individualRoomManagementSection
                audioSettingsSection
                quickStatsSection
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .navigationTitle("🎙️ Host Audio Control")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Quick Messages") {
                    showingQuickCommPanel = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $showingQuickCommPanel) {
            QuickHostCommPanel()
                .environmentObject(hostAudioManager)
                .environmentObject(hostedEventManager)
        }
        .alert("Broadcast Message", isPresented: $showingBroadcastAlert) {
            TextField("Enter message to broadcast", text: $broadcastMessage)
            Button("Send") {
                sendCustomBroadcast()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This message will be sent to all participants")
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host Audio Control")
                        .font(.largeTitle.bold())
                    
                    Text("\(hostedEventManager.participants.count) participants across \(hostedEventManager.tables.count) tables")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Master Status Indicator
                VStack(spacing: 4) {
                    Circle()
                        .fill(masterStatusColor)
                        .frame(width: 16, height: 16)
                    
                    Text(masterStatusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(masterStatusColor)
                }
            }
            
            // Connection Overview Bar
            if !hostAudioManager.activeRooms.isEmpty {
                HStack {
                    ForEach(hostAudioManager.getAllRoomStatuses(), id: \.id) { roomStatus in
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(roomStatus.isConnected ? .green : .gray)
                                .frame(height: 8)
                                .cornerRadius(4)
                            
                            Text("T\(roomStatus.tableNumber)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Broadcast Controls
    private var broadcastControlsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("📢 Global Broadcast")
                    .font(.title2.bold())
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Main Broadcast Button
                Button(action: {
                    if hostAudioManager.isBroadcasting {
                        hostAudioManager.stopBroadcasting()
                    } else {
                        hostAudioManager.broadcastToAllRooms()
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: hostAudioManager.isBroadcasting ? "mic.slash.fill" : "megaphone.fill")
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hostAudioManager.isBroadcasting ? "Stop Broadcasting" : "Broadcast to All")
                                .font(.headline)
                            
                            Text(hostAudioManager.isBroadcasting
                                 ? "You're live to all tables"
                                 : "Speak to all \(hostAudioManager.activeRooms.count) tables")
                                .font(.caption)
                                .opacity(0.8)
                        }
                        
                        Spacer()
                        
                        if hostAudioManager.isBroadcasting {
                            // Broadcasting animation
                            HStack(spacing: 2) {
                                ForEach(0..<3) { index in
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(hostAudioManager.isBroadcasting ? 1.5 : 1.0)
                                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: hostAudioManager.isBroadcasting)
                                }
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(hostAudioManager.isBroadcasting ? .red : .blue)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Quick Broadcast Actions
                HStack(spacing: 12) {
                    Button("Custom Message") {
                        showingBroadcastAlert = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Time Warning") {
                        quickBroadcast("⏰ 30 seconds remaining!")
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Round Complete") {
                        quickBroadcast("🎉 Round complete! Great job everyone!")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.blue.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Individual Room Management
    private var individualRoomManagementSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("🪑 Table Voice Chats")
                    .font(.title2.bold())
                
                Spacer()
                
                // Current Connection Indicator
                if let currentRoom = hostAudioManager.currentConnectedRoom,
                   let roomStatus = hostAudioManager.roomStatuses[currentRoom] {
                    HStack(spacing: 6) {
                        Text("Connected to:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(roomStatus.displayName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            if hostedEventManager.tables.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "table.furniture")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("No active tables")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Tables will appear here when participants join")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(.gray.opacity(0.05))
                .cornerRadius(12)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 16) {
                    ForEach(hostedEventManager.tables, id: \.tableNumber) { table in
                        TableRoomControlCard(
                            table: table,
                            onJoinVoiceChat: {
                                joinTableVoiceChat(table.tableNumber)
                            }
                        )
                        .environmentObject(hostedEventManager)
                    }
                }
            }
        }
    }
    
    // MARK: - Audio Settings
    private var audioSettingsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("🎛️ Audio Settings")
                    .font(.title2.bold())
                Spacer()
            }
            
            VStack(spacing: 16) {
                // Host Volume Control
                VStack(spacing: 8) {
                    HStack {
                        Text("Host Volume")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(Int(hostAudioManager.hostVolume * 100))%")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .frame(width: 50, alignment: .trailing)
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .foregroundColor(.secondary)
                        
                        Slider(value: Binding(
                            get: { hostAudioManager.hostVolume },
                            set: { hostAudioManager.updateHostVolume($0) }
                        ), in: 0...1)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Global Audio Controls
                HStack(spacing: 16) {
                    Button(hostAudioManager.isHostMicMuted ? "Unmute Host Mic" : "Mute Host Mic") {
                        hostAudioManager.toggleHostMic()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(hostAudioManager.isHostMicMuted ? .red : .primary)
                    
                    Button("Mute All Tables") {
                        hostAudioManager.muteAllRooms()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Unmute All Tables") {
                        hostAudioManager.unmuteAllRooms()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.orange.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Quick Stats
    private var quickStatsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("📊 Session Stats")
                    .font(.title3.bold())
                Spacer()
            }
            
            HStack(spacing: 16) {
                StatCard(
                    title: "Active Rooms",
                    value: "\(hostAudioManager.activeRooms.count)",
                    icon: "waveform",
                    color: .blue
                )
                
                StatCard(
                    title: "Connected",
                    value: "\(hostAudioManager.roomStatuses.values.filter(\.isConnected).count)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                StatCard(
                    title: "Total Players",
                    value: "\(hostedEventManager.participants.count)",
                    icon: "person.3.fill",
                    color: .purple
                )
                
                StatCard(
                    title: "Broadcast Time",
                    value: "2m 15s", // Could track actual broadcast time
                    icon: "timer",
                    color: .orange
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var masterStatusColor: Color {
        if hostAudioManager.isBroadcasting {
            return .red
        } else if hostAudioManager.currentConnectedRoom != nil {
            return .green
        } else if !hostAudioManager.activeRooms.isEmpty {
            return .orange
        } else {
            return .gray
        }
    }
    
    private var masterStatusText: String {
        if hostAudioManager.isBroadcasting {
            return "Broadcasting"
        } else if hostAudioManager.currentConnectedRoom != nil {
            return "Connected"
        } else if !hostAudioManager.activeRooms.isEmpty {
            return "Ready"
        } else {
            return "Offline"
        }
    }
    
    // MARK: - Actions
    
    private func joinTableVoiceChat(_ tableNumber: Int) {
        let roomCode = "TBL\(String(format: "%02d", tableNumber))"
        hostAudioManager.joinSpecificRoom(roomCode)
    }
    
    private func quickBroadcast(_ message: String) {
        Task {
            await hostedEventManager.triggerNotification(message)
        }
        hostAudioManager.broadcastToAllRooms()
    }
    
    private func sendCustomBroadcast() {
        guard !broadcastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        quickBroadcast(broadcastMessage)
        broadcastMessage = ""
    }
}

// MARK: - Stat Card Component
struct StatCard: View {
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
                .font(.title3.bold())
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.gray.opacity(0.05))
        .cornerRadius(12)
    }
}
