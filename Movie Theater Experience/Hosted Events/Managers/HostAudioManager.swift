//
//  HostAudioManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/26/25.
//

//
//  HostAudioManager.swift
//  Movie Theater Experience
//
//  Core manager for host audio controls and room management

import Foundation
import SwiftUI
import AVFoundation
import FirebaseFirestore

@MainActor
class HostAudioManager: ObservableObject {
    static let shared = HostAudioManager()
    
    // MARK: - Published Properties
    @Published var isHostMicMuted = false
    @Published var hostVolume: Float = 0.8
    @Published var activeRooms: [String] = []
    @Published var isBroadcasting = false
    @Published var roomStatuses: [String: RoomStatus] = [:]
    @Published var currentConnectedRoom: String?
    @Published var isListeningToAll = false
    
    // MARK: - Private Properties
    private let db = Firestore.firestore(database: "uploads")
    private var audioEngine: AVAudioEngine?
    private var roomListeners: [String: ListenerRegistration] = [:]
    
    // MARK: - Data Structures
    struct RoomStatus: Identifiable {
        let id: String
        let roomCode: String
        let tableNumber: Int
        let participantCount: Int
        let isConnected: Bool
        let averageVolume: Float
        let teamName: String?
        let lastActivity: Date
        
        var displayName: String {
            teamName ?? "Table \(tableNumber)"
        }
    }
    
    private init() {
        setupAudioEngine()
        setupRoomMonitoring()
    }
    
    // MARK: - Core Broadcasting Functions
    
    /// Broadcast host voice to all active rooms simultaneously
    func broadcastToAllRooms() {
        print("🎙️ [Host] Starting broadcast to \(activeRooms.count) rooms")
        
        isBroadcasting = true
        
        // In a real implementation, this would:
        // 1. Create a special broadcast FaceTime call
        // 2. Invite all participants to temporarily join
        // 3. Allow host to speak to everyone at once
        
        // For now, we'll simulate by updating Firebase and opening a broadcast room
        Task {
            await createBroadcastSession()
        }
        
        // Auto-stop broadcasting after reasonable time
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.stopBroadcasting()
        }
    }
    
    /// Stop broadcasting to all rooms
    func stopBroadcasting() {
        print("🔇 [Host] Stopping broadcast")
        
        isBroadcasting = false
        
        Task {
            await endBroadcastSession()
        }
    }
    
    /// Join a specific room for direct communication
    func joinSpecificRoom(_ roomCode: String) {
        print("📞 [Host] Joining room \(roomCode) for direct communication")
        
        // Leave current room if connected
        if let currentRoom = currentConnectedRoom {
            leaveRoom(currentRoom)
        }
        
        let faceTimeLink = "facetime://room/\(roomCode)"
        if let url = URL(string: faceTimeLink) {
            UIApplication.shared.open(url) { success in
                Task { @MainActor in
                    if success {
                        self.currentConnectedRoom = roomCode
                        self.updateRoomConnection(roomCode, connected: true)
                        print("✅ [Host] Connected to room \(roomCode)")
                    } else {
                        print("❌ [Host] Failed to connect to room \(roomCode)")
                    }
                }
            }
        }
    }
    
    /// Leave a specific room
    func leaveRoom(_ roomCode: String) {
        print("🚪 [Host] Leaving room \(roomCode)")
        
        currentConnectedRoom = nil
        updateRoomConnection(roomCode, connected: false)
    }
    
    /// Mute audio from all rooms (host can still speak)
    func muteAllRooms() {
        print("🔇 [Host] Muting all rooms")
        
        isHostMicMuted = false // Host can still speak
        
        // Update room statuses to muted
        for (roomCode, var status) in roomStatuses {
            // In a real implementation, this would mute incoming audio
            roomStatuses[roomCode] = RoomStatus(
                id: status.id,
                roomCode: status.roomCode,
                tableNumber: status.tableNumber,
                participantCount: status.participantCount,
                isConnected: status.isConnected,
                averageVolume: 0.0, // Muted
                teamName: status.teamName,
                lastActivity: status.lastActivity
            )
        }
        
        Task {
            await updateHostAudioSettings(micMuted: false, roomsVolume: 0.0)
        }
    }
    
    /// Unmute audio from all rooms
    func unmuteAllRooms() {
        print("🔊 [Host] Unmuting all rooms")
        
        // Restore normal volume levels
        for (roomCode, var status) in roomStatuses {
            roomStatuses[roomCode] = RoomStatus(
                id: status.id,
                roomCode: status.roomCode,
                tableNumber: status.tableNumber,
                participantCount: status.participantCount,
                isConnected: status.isConnected,
                averageVolume: hostVolume, // Restore volume
                teamName: status.teamName,
                lastActivity: status.lastActivity
            )
        }
        
        Task {
            await updateHostAudioSettings(micMuted: false, roomsVolume: hostVolume)
        }
    }
    
    /// Toggle host microphone mute
    func toggleHostMic() {
        isHostMicMuted.toggle()
        print("🎤 [Host] Microphone \(isHostMicMuted ? "muted" : "unmuted")")
        
        Task {
            await updateHostAudioSettings(micMuted: isHostMicMuted, roomsVolume: hostVolume)
        }
    }
    
    /// Update host volume level
    func updateHostVolume(_ volume: Float) {
        hostVolume = max(0.0, min(1.0, volume))
        print("🔊 [Host] Volume set to \(Int(hostVolume * 100))%")
        
        Task {
            await updateHostAudioSettings(micMuted: isHostMicMuted, roomsVolume: hostVolume)
        }
    }
    
    // MARK: - Room Management
    
    /// Register a new room for monitoring
    func registerRoom(roomCode: String, tableNumber: Int, teamName: String?) {
        let status = RoomStatus(
            id: roomCode,
            roomCode: roomCode,
            tableNumber: tableNumber,
            participantCount: 0,
            isConnected: false,
            averageVolume: hostVolume,
            teamName: teamName,
            lastActivity: Date()
        )
        
        roomStatuses[roomCode] = status
        activeRooms.append(roomCode)
        
        // Start monitoring this room
        startMonitoringRoom(roomCode, tableNumber: tableNumber)
        
        print("📝 [Host] Registered room \(roomCode) for Table \(tableNumber)")
    }
    
    /// Unregister a room
    func unregisterRoom(_ roomCode: String) {
        roomStatuses.removeValue(forKey: roomCode)
        activeRooms.removeAll { $0 == roomCode }
        
        // Stop monitoring
        roomListeners[roomCode]?.remove()
        roomListeners.removeValue(forKey: roomCode)
        
        print("🗑️ [Host] Unregistered room \(roomCode)")
    }
    
    /// Get room status for a specific table
    func getRoomStatus(for tableNumber: Int) -> RoomStatus? {
        return roomStatuses.values.first { $0.tableNumber == tableNumber }
    }
    
    /// Get all active room statuses sorted by table number
    func getAllRoomStatuses() -> [RoomStatus] {
        return roomStatuses.values.sorted { $0.tableNumber < $1.tableNumber }
    }
    
    // MARK: - Private Implementation
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        
        // Configure audio session for host control
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try audioSession.setActive(true)
        } catch {
            print("❌ [Host] Failed to configure audio session: \(error)")
        }
    }
    
    private func setupRoomMonitoring() {
        print("👂 [Host] Setting up room monitoring system")
        // Initialize monitoring systems
    }
    
    private func createBroadcastSession() async {
        do {
            // Create a special broadcast room document in Firebase
            let broadcastData: [String: Any] = [
                "hostId": AppModel.shared.currentUserId,
                "hostName": AppModel.shared.username,
                "isActive": true,
                "message": "Host is broadcasting",
                "timestamp": Date(),
                "activeRooms": activeRooms
            ]
            
            try await db.collection("HostBroadcasts")
                .document("current")
                .setData(broadcastData)
            
            print("✅ [Host] Created broadcast session")
            
        } catch {
            print("❌ [Host] Failed to create broadcast session: \(error)")
        }
    }
    
    private func endBroadcastSession() async {
        do {
            try await db.collection("HostBroadcasts")
                .document("current")
                .updateData([
                    "isActive": false,
                    "endedAt": Date()
                ])
            
            print("✅ [Host] Ended broadcast session")
            
        } catch {
            print("❌ [Host] Failed to end broadcast session: \(error)")
        }
    }
    
    private func updateRoomConnection(_ roomCode: String, connected: Bool) {
        guard var status = roomStatuses[roomCode] else { return }
        
        roomStatuses[roomCode] = RoomStatus(
            id: status.id,
            roomCode: status.roomCode,
            tableNumber: status.tableNumber,
            participantCount: status.participantCount,
            isConnected: connected,
            averageVolume: status.averageVolume,
            teamName: status.teamName,
            lastActivity: Date()
        )
    }
    
    private func updateHostAudioSettings(micMuted: Bool, roomsVolume: Float) async {
        do {
            let audioSettings: [String: Any] = [
                "hostId": AppModel.shared.currentUserId,
                "micMuted": micMuted,
                "roomsVolume": roomsVolume,
                "updatedAt": Date()
            ]
            
            try await db.collection("HostAudioSettings")
                .document(AppModel.shared.currentUserId)
                .setData(audioSettings)
            
        } catch {
            print("❌ [Host] Failed to update audio settings: \(error)")
        }
    }
    
    private func startMonitoringRoom(_ roomCode: String, tableNumber: Int) {
        // Monitor room participant count and activity
        let listener = db.collection("TriviaRooms")
            .document(roomCode)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let data = snapshot?.data() else { return }
                
                Task { @MainActor in
                    let participantCount = data["participantCount"] as? Int ?? 0
                    
                    if var status = self.roomStatuses[roomCode] {
                        self.roomStatuses[roomCode] = RoomStatus(
                            id: status.id,
                            roomCode: status.roomCode,
                            tableNumber: status.tableNumber,
                            participantCount: participantCount,
                            isConnected: status.isConnected,
                            averageVolume: status.averageVolume,
                            teamName: status.teamName,
                            lastActivity: Date()
                        )
                    }
                }
            }
        
        roomListeners[roomCode] = listener
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Clean up listeners
        for listener in roomListeners.values {
            listener.remove()
        }
        roomListeners.removeAll()
        
        // Stop audio engine
        audioEngine?.stop()
    }
}
