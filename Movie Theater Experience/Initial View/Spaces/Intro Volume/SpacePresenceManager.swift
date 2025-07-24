//
//  SpacePresenceManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/11/25.
//

import Foundation
import FirebaseFirestoreInternalWrapper
import UIKit

class SpacePresenceManager {
    static let shared = SpacePresenceManager()
    
    private let db = Firestore.firestore(database: "uploads")
    private var userPresenceListeners: [String: ListenerRegistration] = [:]
    private var userPresenceRefs: [String: DocumentReference] = [:]
    private var userId: String = UUID().uuidString
    
    private init() {
        // Create a unique ID for this user session
        userId = UserDefaults.standard.string(forKey: "spaceUserId") ?? UUID().uuidString
        UserDefaults.standard.set(userId, forKey: "spaceUserId")
        
        // Set up app termination cleanup
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    // Join a space and increment the user count
    func joinSpace(spaceId: String) async {
        guard !userPresenceRefs.keys.contains(spaceId) else {
            print("Already in this space")
            return
        }
        
        do {
            // 1. Update space document to increment user count
            let spaceRef = db.collection("Spaces").document(spaceId)
            try await spaceRef.updateData([
                "currentUserCount": FieldValue.increment(Int64(1))
            ])
            
            // 2. Add user to active users collection
            let userPresenceRef = spaceRef.collection("activeUsers").document(userId)
            try await userPresenceRef.setData([
                "joinedAt": FieldValue.serverTimestamp(),
                "lastUpdate": FieldValue.serverTimestamp(),
                "deviceId": userId
            ])
            
            // 3. Set up a listener to monitor this reference
            let listener = userPresenceRef.addSnapshotListener { [weak self] snapshot, error in
                // If the document is deleted (e.g. by server cleanup), re-add it
                if snapshot?.data() == nil {
                    try? userPresenceRef.setData([
                        "joinedAt": FieldValue.serverTimestamp(),
                        "lastUpdate": FieldValue.serverTimestamp(),
                        "deviceId": self?.userId ?? ""
                    ])
                }
            }
            
            // 4. Store references for cleanup
            userPresenceRefs[spaceId] = userPresenceRef
            userPresenceListeners[spaceId] = listener
            
            // 5. Set up periodic heartbeat updates
            startHeartbeat(for: spaceId)
            
            print("Successfully joined space: \(spaceId)")
        } catch {
            print("Error joining space: \(error.localizedDescription)")
        }
    }
    
    // Leave a space and decrement the user count
    func leaveSpace(spaceId: String) async {
        guard let presenceRef = userPresenceRefs[spaceId] else {
            print("Not currently in this space")
            return
        }
        
        do {
            // 1. Decrement user count in space document
            let spaceRef = db.collection("Spaces").document(spaceId)
            try await spaceRef.updateData([
                "currentUserCount": FieldValue.increment(Int64(-1))
            ])
            
            // 2. Remove user from active users
            try await presenceRef.delete()
            
            // 3. Clean up listeners and references
            userPresenceListeners[spaceId]?.remove()
            userPresenceListeners.removeValue(forKey: spaceId)
            userPresenceRefs.removeValue(forKey: spaceId)
            
            print("Successfully left space: \(spaceId)")
        } catch {
            print("Error leaving space: \(error.localizedDescription)")
        }
    }
    
    // Heartbeat to keep presence alive
    private func startHeartbeat(for spaceId: String) {
        let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let presenceRef = self?.userPresenceRefs[spaceId] else { return }
            
            // Update lastActive timestamp
            presenceRef.updateData([
                "lastUpdate": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("Error updating heartbeat: \(error.localizedDescription)")
                }
            }
        }
        
        // Store timer
        RunLoop.current.add(timer, forMode: .common)
    }
    
    // Cleanup on app termination
    @objc private func handleAppTermination() {
        // For each space we're in, decrement count and remove presence
        for spaceId in userPresenceRefs.keys {
            let spaceRef = db.collection("Spaces").document(spaceId)
            spaceRef.updateData([
                "currentUserCount": FieldValue.increment(Int64(-1))
            ])
            
            userPresenceRefs[spaceId]?.delete()
        }
    }
    
    // Cleanup all spaces on deinit
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        // Remove all listeners
        for listener in userPresenceListeners.values {
            listener.remove()
        }
    }
}
