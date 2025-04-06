//
//  VideoSync.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/28/25.
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseCore
import AVFoundation
import Observation // Make sure to import Observation


enum VideoSyncError: Error {
    case missingDatabase
    case missingEventId
    case invalidPath(String)
    case firestoreError(String)
}

enum CleanupLevel {
    case full    // Complete cleanup
    case partial // Maintain sync state but cleanup player
    case light   // Just cleanup current player
}

@Observable
class VideoSyncService {
    
    enum ViewState {
        case immersive
        case movieWindow
        case none
    }
    // Make the snapshot type public
    public struct SyncSnapshot {
        let position: Double
        let isPlaying: Bool
    }

    // Add public property to access snapshot
    private(set) var currentSnapshot: SyncSnapshot?
    
    // Make the view state accessible
    private(set) var currentViewState: ViewState = .none
    
    
    // MARK: - Public / Observable
    var isHost = false
    var isWithinEventTime = false
    var lastError: Error?
    var isPlaying: Bool { isPlayingState } // Add this public getter
    var currentTime = 0.0
    var dismissWindow: ((String) -> Void)?
    var dismissImmersiveSpace: (() -> Void)?
    
    

    
    // MARK: - Private
    private var isPlayingState = false // Keep the actual state private but add the public getter above
    private let db: Firestore
    private var lastPresenceUpdate: Date?
    private let spaceManager = ImmersiveSpaceManager.shared

    
    /// The *actual* player we are syncing with.
    /// We keep it here so we can remove the time observer from
    /// this exact instance in `cleanup()`.
    private(set) var currentPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var syncSnapshot: (position: Double, isPlaying: Bool)?
    private var isPlayStateListenerActive = false
    private var lastSyncUpdate: Date?

    // Other properties...
    private let joinTime = Date()
    private(set) var activeViewerCount: Int = 0
    
    // Room info
    private var event: CalendarEvent?
    private var eventId: String?
    private var userId: String?
    
    // Firebase listeners
    private var listeners: [ListenerRegistration?] = []
    private var timers: [Timer?] = []
    
    // Constants
    private let syncThreshold = 3.0
    private let presenceInterval = 10.0
    
    // Singleton
    static let shared = VideoSyncService()
    
    // MARK: - Init
    private init() {
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = false
        settings.isSSLEnabled = true
        
        self.db = Firestore.firestore(database: "movieexperiencedb")
        self.db.settings = settings
    }
    
    // MARK: - Public Methods
    func configureSync(eventId: String, userId: String, event: CalendarEvent) -> Bool {
        self.eventId = eventId
        self.userId = userId
        self.event = event
        
        // Update event time
        updateEventTimeStatus()
        guard isWithinEventTime else {
            print("❌ Outside event time window, cannot sync")
            return false
        }
        
        Task {
            await initializeRoom()
            startMonitoring()
        }
        return true
    }
    
    func startSync(with newPlayer: AVPlayer) {
        print("🔄 VideoSyncService starting sync...")
        guard isWithinEventTime else {
            print("❌ Cannot sync - outside event time")
            return
        }
        
        // Guard against multiple syncs
        if currentPlayer == newPlayer {
            print("⚠️ Sync already running for this player")
            return
        }
        
        // Remove old observer if needed
        removeTimeObserverIfNeeded()
        
        // Set the new player
        self.currentPlayer = newPlayer
        print("👉 New player set")
        
        guard newPlayer.status == .readyToPlay else {
            print("⏳ Waiting for player to be ready...")
            // Set up one-time observation for player readiness
            var statusObservation: NSKeyValueObservation?
            statusObservation = newPlayer.observe(\.status) { [weak self] player, _ in
                guard let self = self, player.status == .readyToPlay else { return }
                self.continueSync(with: player)
                statusObservation?.invalidate()
            }
            return
        }
        
        continueSync(with: newPlayer)
    }
    
    private func continueSync(with player: AVPlayer) {
        print("✅ Player is ready, continuing sync...")

        // 1️⃣ Add a periodic time observer to track playback time
        setupTimeObservation(player)
        print("⏱️ Time observation setup complete")

        // 2️⃣ Ensure Firebase sync is properly configured
        if !isPlayStateListenerActive {
            print("🔥 Setting up new Firebase sync listener")
            setupVideoSync()
        } else {
            print("🔄 Reusing existing Firebase sync listener")
        }

        // 3️⃣ Apply initial play state based on snapshot or host settings
        Task {
            if let snapshot = currentSnapshot {
                print("📸 Using snapshot for initial state - Position: \(snapshot.position), Playing: \(snapshot.isPlaying)")
                
                // ✅ Ensure seeking completes before updating state
                await player.seek(
                    to: CMTime(seconds: snapshot.position, preferredTimescale: 1000),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                print("✅ Initial seek complete")

                // ✅ Ensure the snapshot's play state is restored only **after** seek completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if snapshot.isPlaying {
                        player.play()
                        print("▶️ Resuming playback")
                    }
                }
                clearSnapshot()
            } else if isHost {
                print("🎮 Host setting initial play state")
                handlePlayPause(isPlaying: true)
            }
        }

        print("✅ Sync initialization complete")
    }



    
    func handleVideoEnd() {
        print("❌ Handling video end, stopping playback, cleaning up")
        
        handlePlayPause(isPlaying: false)
        cleanup()
    }
    
    // In VideoSyncService.swift
    func switchToView(_ state: ViewState) {
        print("🔄 Switching to view: \(state)")

        // 1️⃣ Check if we are already in this state to prevent redundant operations
        guard currentViewState != state else {
            print("⚠️ Already in the desired view state: \(state). No action needed.")
            return
        }

        // 2️⃣ Remove old time observer to prevent duplicate updates
        removeTimeObserverIfNeeded()

        // 3️⃣ Store playback snapshot only if there’s a meaningful change
        if let player = currentPlayer {
            let currentPosition = currentTime // Use the synced playback position
            let isCurrentlyPlaying = player.timeControlStatus == .playing

            // Only store snapshot if time difference is significant (> 0.5 sec)
            if let lastSnapshot = currentSnapshot, abs(lastSnapshot.position - currentPosition) < 0.5 {
                print("🔄 Skipping snapshot update (time difference too small)")
            } else {
                print("📸 Creating snapshot - Position: \(currentPosition), Playing: \(isCurrentlyPlaying)")
                currentSnapshot = SyncSnapshot(position: currentPosition, isPlaying: isCurrentlyPlaying)
            }
        }

        // 4️⃣ Update the current view state
        currentViewState = state

        // 5️⃣ Manage view transitions
        if state == .movieWindow {
            print("📱 Entering movie window mode")

            // Hide immersive screen if present
            if let screenEntity = TheatreEntityWrapper.shared.screenEntity {
                Task {
                    await MainActor.run {
                        screenEntity.isEnabled = false
                    }
                }
            }

            // Ensure immersive space is dismissed before showing the movie window
            Task {
                await MainActor.run {
                    dismissImmersiveSpace?()
                    dismissWindow?("immersiveWindow") // Ensure immersive UI is fully dismissed
                }
            }

        } else if state == .immersive {
            print("🎥 Entering immersive mode")

            // Restore immersive screen if present
            if let screenEntity = TheatreEntityWrapper.shared.screenEntity {
                Task {
                    await MainActor.run {
                        screenEntity.isEnabled = true
                    }
                }
            }

            // Ensure movie window is dismissed before showing immersive mode
            Task {
                await MainActor.run {
                    dismissWindow?("movieWindow")
                }
            }
        }

        print("✅ View state switch complete: \(state)")
    }



    
    func clearSnapshot() {
        currentSnapshot = nil
    }
    
    func storePlaybackSnapshot(position: Double, isPlaying: Bool) {
        self.currentSnapshot = SyncSnapshot(position: position, isPlaying: isPlaying)
        print("📸 Snapshot stored - Position: \(position), Playing: \(isPlaying)")
    }
    
    func handleVideoEnd() async {
        print("🎬 Handling video end in VideoSyncService...")

        guard let syncRef = getBasePath() else {
            print("❌ No valid Firestore path found for cleanup.")
            return
        }

        do {
            // 1️⃣ Mark session as completed in Firestore
            try await syncRef.document("playState").updateData([
                "isPlaying": false,
                "playbackPosition": 0.0, // Reset position
                "sessionEnded": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            print("✅ Firestore session marked as completed.")

            // 2️⃣ Prevent late sync updates from resuming playback
            isPlayStateListenerActive = false
            removeTimeObserverIfNeeded()

            // 3️⃣ Capture last playback position (for user history)
            if let player = currentPlayer {
                let lastPosition = player.currentTime().seconds
                print("📍 Storing last playback position: \(lastPosition)")
                currentSnapshot = SyncSnapshot(position: lastPosition, isPlaying: false)
            }

            // 4️⃣ Cleanup video sync service to prevent orphaned listeners
            cleanup(level: .full)

            // 5️⃣ If in immersive space, transition user properly
            if case .open = await spaceManager.state {
                await spaceManager.initiateCleanup()

                // ✅ Directly call `dismissImmersiveSpace()`
                print("🚪 Dismissing immersive space...")
                await spaceManager.dismissImmersiveSpace()
            }

            // 6️⃣ Close all related UI windows and show exit screen
            dismissWindow?("movieWindow")
            try? await Task.sleep(for: .milliseconds(100)) // Ensure UI state settles
            dismissWindow?("chatWindow")
            dismissWindow?("emojiWindow")

            print("✅ Video end handling complete.")

        } catch {
            print("❌ Error during video end cleanup: \(error.localizedDescription)")
            handleError(error)
        }
    }

    
    
    func handlePlayPause(isPlaying: Bool) {
        // 1️⃣ Ensure Firestore and playback state only update if there’s an actual change
        guard isHost,
              isWithinEventTime,
              let syncRef = getBasePath(),
              isPlayingState != isPlaying else {
            print("⚠️ No change in play state. Skipping Firestore update.")
            return
        }

        // 2️⃣ Update local play state
        isPlayingState = isPlaying

        // 3️⃣ Prevent redundant play/pause calls
        if let player = currentPlayer {
            if isPlaying, player.timeControlStatus != .playing {
                player.play()
                print("▶️ Player started playing")
            } else if !isPlaying, player.timeControlStatus != .paused {
                player.pause()
                print("⏸️ Player paused")
            }
        }

        // 4️⃣ Debounce Firestore writes to avoid excessive updates
        let now = Date()
        if let lastUpdate = lastSyncUpdate, now.timeIntervalSince(lastUpdate) < 1.0 {
            print("🔄 Skipping Firestore write due to debounce")
            return
        }
        lastSyncUpdate = now

        // 5️⃣ Update Firestore state
        syncRef.document("playState").setData([
            "isPlaying": isPlaying,
            "playbackPosition": currentTime,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": UUID().uuidString
        ], merge: true) { error in
            if let error = error {
                print("❌ Failed to update Firestore play state: \(error)")
            }
        }

        print("✅ Play state updated in Firestore: \(isPlaying ? "Playing" : "Paused")")
    }

    
    private func cleanupListeners() {
        print("🧹 Cleaning up listeners")
        listeners.forEach { $0?.remove() }
        listeners.removeAll()
        isPlayStateListenerActive = false
    }
    
    func getWatchStats() -> WatchStats {
        return WatchStats(
            watchTime: Date().timeIntervalSince(joinTime),
            viewerCount: activeViewerCount
        )
    }
    
    private func setupPresenceListener() {
        guard let syncRef = getBasePath() else { return }
        
        let presenceListener = syncRef.document("presence")
            .collection("activeViewers")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let documents = snapshot?.documents else { return }
                
                self.activeViewerCount = documents.count
            }
        
        listeners.append(presenceListener)
    }
    
    private func removeTimeObserverIfNeeded() {
        // 1️⃣ Ensure there is an observer to remove
        guard let token = timeObserverToken, let player = currentPlayer else {
            print("ℹ️ No time observer to remove")
            return
        }

        // 2️⃣ Remove observer and clean up the reference
        print("🧹 Removing old time observer from player")
        player.removeTimeObserver(token)
        timeObserverToken = nil // ✅ Properly clean up

        print("✅ Time observer removed successfully")
    }

    
    
    // MARK: - Add a periodic time observer
    private func setupTimeObservation(_ player: AVPlayer) {
        print("⏱️ Setting up time observation for player")

        // 1️⃣ Remove existing time observer before adding a new one
        removeTimeObserverIfNeeded()

        // 2️⃣ Define update interval
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            // 3️⃣ Ensure player is active
            if player.timeControlStatus == .paused {
                print("⏸️ Player is paused, skipping Firestore update.")
                return
            }

            // 4️⃣ Update the current time
            self.currentTime = time.seconds
            print("📌 Time observer update: \(time.seconds)")

            // 5️⃣ Debounce Firestore updates (every 1.5s, but at least every 5s)
            let now = Date()
            let elapsedTime = now.timeIntervalSince(self.lastSyncUpdate ?? .distantPast)

            if elapsedTime < 1.5 && (elapsedTime < 5.0 || self.currentTime.truncatingRemainder(dividingBy: 5.0) != 0) {
                print("⏳ Skipping Firestore update: Too soon since last update (\(elapsedTime)s)")
                return
            }
            self.lastSyncUpdate = now

            // 6️⃣ Firestore update
            if self.isHost {
                print("📤 Host updating Firestore with playback position: \(self.currentTime)")
                guard let syncRef = self.getBasePath() else {
                    print("❌ getBasePath() returned nil")
                    return
                }

                syncRef.document("playState").setData([
                    "playbackPosition": self.currentTime,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true) { error in
                    if let error = error {
                        print("❌ Firestore update failed: \(error.localizedDescription)")
                    } else {
                        print("✅ Firestore successfully updated: \(self.currentTime)")
                    }
                }
            }
        }

        print("✅ Time observation setup complete")
    }
    

    private func cleanupTimers() {
       print("🧹 Cleaning up timers")
       timers.forEach { $0?.invalidate() }
       timers.removeAll()
    }
    
    func cleanup(level: CleanupLevel = .full) {
        print("=== VideoSyncService cleanup (level: \(level)) ===")

        // Always remove time observer first
        removeTimeObserverIfNeeded()

        switch level {
        case .full:
            print("🧹 Performing full cleanup")
            NotificationCenter.default.removeObserver(self)
            Task {
                await ensureHostCleanup()
                if let eid = eventId, let uid = userId {
                    await cleanupDatabasePresence(eventId: eid, userId: uid)
                }
                cleanupListeners()
                cleanupTimers()
                resetState()

                // ✅ Only clear snapshot if movie window is NOT open
                clearSnapshot()

                isPlayStateListenerActive = false
            }

        case .partial:
            print("🧹 Performing partial cleanup")
            // Just cleanup player but maintain Firebase state and listeners
            currentPlayer = nil
            print("✅ Retaining playback snapshot for later sync")
            print("✅ Firebase listeners active: \(isPlayStateListenerActive)")
            print("📡 Maintaining sync state and database connection")

        case .light:
            print("🧹 Performing light cleanup")
            // ✅ Just cleanup current player but keep sync data
            currentPlayer = nil
            print("✅ Firebase listeners active: \(isPlayStateListenerActive)")
            print("📡 Maintaining all sync state and connections")
            if isHost {
                print("🎮 Maintaining host status")
            }
        }

        // ✅ Log cleanup completion with details
        print("=== Cleanup Summary ===")
        print("🎯 Cleanup level: \(level)")
        print("🔌 Player removed: \(currentPlayer == nil)")
        print("🔥 Firebase active: \(isPlayStateListenerActive)")
        print("👑 Host status: \(isHost)")
        print("✅ Cleanup complete")
    }


    
    // MARK: - Private Setup Methods
    private func initializeRoom() async {
        print("🏠 Initializing video sync room...")

        guard let syncRef = getBasePath() else {
            print("❌ Failed to get Firestore path for room initialization")
            return
        }

        do {
            // 1️⃣ Efficiently check if room is empty
            let activeViewers = try await syncRef.document("presence")
                .collection("activeViewers")
                .limit(to: 1) // ✅ Reduced Firestore reads
                .getDocuments()

            // 2️⃣ If room is empty, create initial room state and elect a host
            if activeViewers.isEmpty {
                print("🆕 No active viewers found, initializing room...")
                try await createInitialRoomState(in: syncRef)
                await becomeHost()
            } else {
                print("✅ Room already exists, skipping initialization")
            }

            // 3️⃣ Ensure room creation completes before registering presence
            await registerPresence()

        } catch {
            print("❌ Error initializing room: \(error.localizedDescription)")
            handleError(error)
        }
    }

    
    func handleAppTermination() {
        print("⚠️ App is terminating. Performing final cleanup...")
        
        // Ensure we have an event ID and user ID.
        guard let eventId = eventId, let userId = userId else {
            print("❌ Termination cleanup failed: Missing event ID or user ID")
            return
        }
        
        Task {
            do {
                // Retrieve the base Firestore path.
                guard let syncRef = getBasePath() else {
                    print("❌ Failed to get Firestore base path during termination")
                    return
                }
                
                // Retrieve the host document.
                let hostRef = syncRef.document("host")
                let hostDoc = try await hostRef.getDocument()
                
                // Check if the current user is the host.
                if let currentHost = hostDoc.data()?["hostId"] as? String, currentHost == userId {
                    print("⚠️ App is terminating and current user is the host. Initiating host election...")
                    await initiateHostElection()
                }
                
                // Remove the user's presence.
                let presenceRef = syncRef.document("presence").collection("activeViewers").document(userId)
                try? await presenceRef.setData(["status": "disconnected"], merge: true)
                try? await presenceRef.delete()
                
                // Optionally update historical records or perform additional cleanup.
                await cleanupDatabasePresence(eventId: eventId, userId: userId)
                
                // Clean up any active listeners, timers, and reset internal state.
                cleanupListeners()
                cleanupTimers()
                removeTimeObserverIfNeeded()
                resetState()
                
                print("✅ Cleanup completed successfully before app termination.")
            } catch {
                print("❌ Error during app termination cleanup: \(error.localizedDescription)")
                handleError(error)
            }
        }
    }



    func applicationWillTerminate(_ application: UIApplication) {
        VideoSyncService.shared.handleAppTermination()
    }
    
    private func setupVideoSync() {
        print("🔄 Setting up video sync...")

        guard let syncRef = getBasePath() else {
            print("❌ Failed to get base path")
            return
        }

        // 1️⃣ Prevent multiple listeners (avoid duplicate reads)
        guard !isPlayStateListenerActive else {
            print("ℹ️ PlayState listener already active, maintaining existing sync")
            return
        }

        print("👂 Setting up new playState listener")
        let playStateListener = syncRef.document("playState")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("❌ PlayState listener error: \(error.localizedDescription)")
                    return
                }

                guard let data = snapshot?.data(),
                      let playbackPosition = data["playbackPosition"] as? Double,
                      let isPlaying = data["isPlaying"] as? Bool else {
                    print("⚠️ Missing data in playState snapshot")
                    if let data = snapshot?.data() {
                        print("📄 Available data: \(data)")
                    }
                    return
                }

                print("📥 Received playState update - Position: \(playbackPosition), Playing: \(isPlaying)")

                // 2️⃣ Prevent unnecessary updates (Only update if there's a real change)
                if self.currentTime == playbackPosition && self.isPlayingState == isPlaying {
                    print("⚠️ No significant change detected in playState. Skipping update.")
                    return
                }

                // 3️⃣ Update our local state
                self.currentTime = playbackPosition
                self.isPlayingState = isPlaying

                // 4️⃣ If we are not the host, adjust the player to match Firestore state
                if !self.isHost {
                    print("👥 Non-host: updating to server state")
                    self.handleServerPlayState(isPlaying: isPlaying, seconds: playbackPosition)
                }
            }

        listeners.append(playStateListener)
        isPlayStateListenerActive = true
        print("✅ Video sync setup complete with new listener")
    }


    
    private func startMonitoring() {
        // Event time monitoring
        let eventTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkEventTime()
        }
        
        // Presence update timer
        let presenceTimer = Timer.scheduledTimer(withTimeInterval: presenceInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.updatePresence()
            }
        }
        
        timers.append(contentsOf: [eventTimer, presenceTimer])
    }
    
    // MARK: - Helper Methods
    private func getBasePath() -> CollectionReference? {
        // 1️⃣ Ensure eventId exists before proceeding
        guard let eventId = eventId else {
            handleError(VideoSyncError.missingEventId)
            print("❌ getBasePath() failed: Missing event ID")
            return nil
        }

        // 2️⃣ Use a cached DateFormatter for better performance
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yyyy"
            formatter.timeZone = TimeZone(identifier: "UTC") // Ensure consistency across users
            return formatter
        }()

        let dateString = dateFormatter.string(from: Date())

        // 3️⃣ Construct Firestore path safely
        let basePath = db.collection("Public Rooms")
                         .document(dateString)
                         .collection("Events")
                         .document(eventId)
                         .collection("sync")

        print("📂 Firestore base path resolved: \(basePath.path)")
        return basePath
    }

    
    private func handleServerPlayState(isPlaying: Bool, seconds: Double) {
        print("🎮 Handling server state update - Playing: \(isPlaying), Position: \(seconds)")

        guard let player = currentPlayer else {
            print("❌ No player available to sync state")
            return
        }

        // 1️⃣ Calculate the time difference (drift)
        let currentTime = player.currentTime().seconds
        let drift = abs(currentTime - seconds)

        // 2️⃣ Handle playback position correction
        if drift > syncThreshold {
            // If drift is large, perform a direct seek
            print("⏱️ Large desync detected (\(drift)s), seeking to sync position: \(seconds)")
            Task {
                await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000),
                                  toleranceBefore: .zero,
                                  toleranceAfter: .zero)
                print("✅ Seek completed")
            }
        } else if drift > 0.1 {
            // If drift is small, adjust playback speed temporarily to correct smoothly
            print("🔄 Small desync detected (\(drift)s), adjusting playback speed for correction")
            player.rate = isPlaying ? 1.05 : 0.95 // Slight speed adjustment
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                player.rate = 1.0 // Reset speed after correction
            }
        } else {
            print("✅ Playback is already in sync (drift: \(drift)s)")
        }

        // 3️⃣ Adjust play/pause state only if necessary
        if isPlaying && player.timeControlStatus != .playing {
            print("▶️ Resuming playback")
            player.play()
        } else if !isPlaying && player.timeControlStatus != .paused {
            print("⏸️ Pausing playback")
            player.pause()
        }

        print("✅ Server state synchronization complete")
    }

    
    private func stopOperations() {
        // Stop timers
        timers.forEach { $0?.invalidate() }
        timers.removeAll()
        
        // Remove listeners
        listeners.forEach { $0?.remove() }
        listeners.removeAll()
        
        // Stop playback
        currentPlayer?.pause()
    }
    
    private func resetState() {
       print("🔄 Resetting service state")
       isHost = false
       isWithinEventTime = false
       isPlayingState = false
       currentPlayer = nil
       eventId = nil
       userId = nil
       event = nil
       currentViewState = .none
    }
    
    private func handleError(_ error: Error) {
        print("Error: \(error.localizedDescription)")
        lastError = error
    }
}

// MARK: - Room State Management
extension VideoSyncService {
    private func createInitialRoomState(in syncRef: CollectionReference) async throws {
        print("Creating initial room state...")
        
        let batch = db.batch()
        
        // Host document
        let hostDoc = syncRef.document("host")
        batch.setData([
            "hostId": userId ?? "",
            "timestamp": FieldValue.serverTimestamp(),  // This remains a true timestamp
            "lastActive": FieldValue.serverTimestamp(),
            "status": "active"
        ], forDocument: hostDoc)
        
        // Play state document
        let playStateDoc = syncRef.document("playState")
        batch.setData([
            "isPlaying": true,
            "playbackPosition": 0.0,  // Renamed
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: playStateDoc)
        
        // Presence document
        let presenceDoc = syncRef.document("presence")
        batch.setData([
            "activeViewerCount": 1,
            "lastUpdated": FieldValue.serverTimestamp()
        ], forDocument: presenceDoc)
        
        // Room state document
        let stateDoc = syncRef.document("state")
        batch.setData([
            "currentUsers": [userId ?? ""],
            "lastUpdated": FieldValue.serverTimestamp(),
            "status": "active"
        ], forDocument: stateDoc)
        
        try await batch.commit()
        print("✅ Initial room state created")
    }
    
    private func setupHostListener() {
        guard let syncRef = getBasePath() else { return }
        
        let hostListener = syncRef.document("host")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let data = snapshot?.data(),
                      let hostId = data["hostId"] as? String else {
                    // No host, initiate election
                    Task { [weak self] in
                        await self?.initiateHostElection()
                    }
                    return
                }
                
                // Update host status
                let wasHost = self.isHost
                self.isHost = (hostId == self.userId)
                
                if wasHost != self.isHost {
                    print("Host status changed: \(self.isHost)")
                }
            }
        
        listeners.append(hostListener)
    }
    
    func initiateHostElection() async {
        print("🗳️ Initiating host election...")

        guard let syncRef = getBasePath(), let userId = userId else {
            print("❌ Host election failed: Missing Firestore path or user ID")
            return
        }

        do {
            // 1️⃣ Check if a host already exists before proceeding
            let hostDoc = try await syncRef.document("host").getDocument()
            if let existingHost = hostDoc.data()?["hostId"] as? String, !existingHost.isEmpty {
                print("ℹ️ Host already exists: \(existingHost), skipping election")
                return
            }

            // 2️⃣ Find the earliest active viewer (excluding current user)
            let viewers = try await syncRef.document("presence")
                .collection("activeViewers")
                .whereField("userId", isNotEqualTo: userId)
                .order(by: "lastSeen", descending: false) // Oldest first
                .limit(to: 1) // ✅ Fetch only the first eligible user
                .getDocuments()

            if let nextHost = viewers.documents.first?.documentID {
                print("👑 Assigning new host: \(nextHost)")

                // 3️⃣ Update Firestore with new host assignment
                try await syncRef.document("host").setData([
                    "hostId": nextHost,
                    "timestamp": FieldValue.serverTimestamp(),
                    "status": "active"
                ])

                print("✅ New host assigned: \(nextHost)")

            } else {
                // 4️⃣ No eligible viewers left, mark session as inactive
                print("⚠️ No eligible users found, marking room as inactive")
                try await syncRef.document("state").updateData([
                    "status": "inactive",
                    "lastUpdated": FieldValue.serverTimestamp()
                ])
            }

        } catch {
            print("❌ Error during host election: \(error.localizedDescription)")
            handleError(error)

            // 5️⃣ Retry mechanism (wait 1 second, then try again)
            print("🔄 Retrying host election in 1 second...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await initiateHostElection() // Recursive retry
        }
    }

    
    private func becomeHost() async {
        print("👑 Attempting to become host...")
        
        guard let syncRef = getBasePath(), let userId = userId else {
            print("❌ Cannot become host: Missing Firestore path or user ID")
            return
        }
        
        do {
            // 1️⃣ Check if a host already exists before proceeding
            let hostDoc = try await syncRef.document("host").getDocument()
            if let existingHost = hostDoc.data()?["hostId"] as? String, !existingHost.isEmpty {
                print("ℹ️ Host already exists: \(existingHost), skipping host assignment")
                return
            }
            
            // 2️⃣ Assign current user as host
            try await syncRef.document("host").setData([
                "hostId": userId,
                "timestamp": FieldValue.serverTimestamp(),
                "lastActive": FieldValue.serverTimestamp(),
                "status": "active"
            ])
            
            // 3️⃣ Confirm host role and update local state
            isHost = true
            print("✅ Successfully became host: \(userId)")
            
        } catch {
            print("❌ Error while becoming host: \(error.localizedDescription)")
            handleError(error)
            
            // 4️⃣ Retry mechanism (attempt again after 1 second)
            print("🔄 Retrying host assignment in 1 second...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await becomeHost() // Recursive retry
        }
    }
}

// MARK: - Presence Management
extension VideoSyncService {
    private func registerPresence() async {
        print("👤 Registering user presence...")

        guard let syncRef = getBasePath(), let userId = userId else {
            print("❌ Failed to register presence: Missing Firestore path or user ID")
            return
        }

        do {
            let presenceRef = syncRef.document("presence").collection("activeViewers").document(userId)

            // 1️⃣ Check if the user is already registered to avoid duplicate writes
            let existingPresence = try await presenceRef.getDocument()
            if existingPresence.exists {
                print("ℹ️ User is already registered in presence list, updating timestamp")
                
                // 2️⃣ Update last seen time instead of re-registering
                try await presenceRef.updateData([
                    "lastSeen": FieldValue.serverTimestamp()
                ])
                return
            }

            // 3️⃣ If not registered, add user to presence list
            print("🆕 Registering new user in presence list")
            try await presenceRef.setData([
                "userId": userId,
                "lastSeen": FieldValue.serverTimestamp(),
                "joined": FieldValue.serverTimestamp(),
                "status": "active"
            ])

            // 4️⃣ Ensure the user is removed if they disconnect (prevents ghost viewers)
            presenceRef.addSnapshotListener { snapshot, error in
                if snapshot?.exists == false {
                    Task {
                        try? await presenceRef.delete()
                    }
                }
            }

            print("✅ Presence registered successfully")

        } catch {
            print("❌ Error registering presence: \(error.localizedDescription)")
            handleError(error)

            // 5️⃣ Retry logic (wait 1 second, then try again)
            print("🔄 Retrying presence registration in 1 second...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await registerPresence() // Recursive retry
        }
    }

    
    private func updatePresence() async {
        guard let syncRef = getBasePath() else { return }

        do {
            let presenceRef = syncRef.document("presence")
                .collection("activeViewers")
                .document(userId ?? "")

            let docSnapshot = try await presenceRef.getDocument()
            if !docSnapshot.exists {
                print("⚠️ Presence document does not exist, creating it")
                try await presenceRef.setData([
                    "userId": userId ?? "",
                    "lastSeen": FieldValue.serverTimestamp(),
                    "timestamp": currentTime,
                    "isHost": isHost
                ])
            } else {
                print("📤 Updating existing presence document")
                try await presenceRef.updateData([
                    "lastSeen": FieldValue.serverTimestamp(),
                    "timestamp": currentTime,
                    "isHost": isHost
                ])
            }

            // Update host status if needed
            if isHost {
                let hostRef = syncRef.document("host")
                let hostSnapshot = try await hostRef.getDocument()
                if hostSnapshot.exists {
                    try await hostRef.updateData([
                        "lastActive": FieldValue.serverTimestamp()
                    ])
                } else {
                    print("⚠️ Host document missing, creating new one")
                    try await hostRef.setData([
                        "hostId": userId ?? "",
                        "timestamp": FieldValue.serverTimestamp(),
                        "status": "active"
                    ])
                }
            }
        } catch {
            print("❌ Firestore update failed: \(error.localizedDescription)")
        }
    }



    
    private func cleanupDatabasePresence(eventId: String, userId: String) async {
        print("🧹 Starting database cleanup for user: \(userId)")

        guard let syncRef = getBasePath() else {
            print("❌ Failed to get Firestore path for cleanup")
            return
        }

        let presenceRef = syncRef.document("presence").collection("activeViewers").document(userId)
        let hostRef = syncRef.document("host")

        do {
            // 1️⃣ Check if the user is the current host before removing them
            let hostDoc = try await hostRef.getDocument()
            if let currentHost = hostDoc.data()?["hostId"] as? String, currentHost == userId {
                print("⚠️ User being removed is the current host. Initiating host election...")
                await initiateHostElection()
            }

            // 2️⃣ Remove user from active viewers
            try await presenceRef.delete()
            print("✅ User removed from active viewers: \(userId)")

            // 3️⃣ Verify that the user was actually removed
            let checkDoc = try await presenceRef.getDocument()
            if checkDoc.exists {
                print("❌ Warning: User document still exists after deletion. Retrying...")
                try await presenceRef.delete()
            }

            // 4️⃣ Update historical viewer data if it exists
            let historicalRef = syncRef.document("presence").collection("historicalViewers").document(userId)
            do {
                try await historicalRef.updateData([
                    "lastSeen": FieldValue.serverTimestamp(),
                    "watchTime": FieldValue.increment(Date().timeIntervalSince(joinTime)),
                    "completedViewing": true
                ])
                print("✅ Updated historical viewer record for \(userId)")
            } catch {
                print("ℹ️ No historical viewer record found for \(userId), skipping update.")
            }

        } catch {
            print("❌ Error cleaning up database presence: \(error.localizedDescription)")
            handleError(error)

            // 5️⃣ Retry with exponential backoff (1s → 2s → 4s)
            for attempt in 1...3 {
                let delay = pow(2.0, Double(attempt))
                print("🔄 Retrying database cleanup in \(Int(delay)) seconds...")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await cleanupDatabasePresence(eventId: eventId, userId: userId)
            }
        }
    }

    
    private func handleHostCleanup(_ syncRef: CollectionReference) async {
        do {
            // Find next potential host
            let viewers = try await syncRef.document("presence")
                .collection("activeViewers")
                .whereField("userId", isNotEqualTo: userId ?? "")
                .order(by: "userId")
                .limit(to: 1)
                .getDocuments()
            
            if let nextHost = viewers.documents.first {
                // Assign new host
                try await syncRef.document("host").setData([
                    "hostId": nextHost.documentID,
                    "timestamp": FieldValue.serverTimestamp(),
                    "status": "active"
                ])
            } else {
                // No other viewers, mark room as completed
                try await syncRef.document("state").updateData([
                    "status": "completed",
                    "lastUpdated": FieldValue.serverTimestamp()
                ])
            }
        } catch {
            handleError(error)
        }
    }
}

// MARK: - Event Time Management
extension VideoSyncService {
    private func updateEventTimeStatus() {
        guard let event = event else {
            isWithinEventTime = false
            return
        }
        
        let now = Date()
        isWithinEventTime = now >= event.date && now <= event.end
        
        if !isWithinEventTime {
            currentPlayer?.pause()
        }
    }
    
    private func checkEventTime() {
        let wasWithinTime = isWithinEventTime
        updateEventTimeStatus()
        
        if wasWithinTime && !isWithinEventTime {
            cleanup()
        }
    }
    
    private func ensureHostCleanup() async {
        guard let syncRef = getBasePath() else { return }
        
        // First, remove self as host if we are the current host
        if isHost {
            do {
                let hostDoc = try await syncRef.document("host").getDocument()
                if let hostId = hostDoc.data()?["hostId"] as? String,
                   hostId == userId {
                    // Remove ourselves as host
                    try await syncRef.document("host").updateData([
                        "status": "inactive",
                        "lastActive": FieldValue.serverTimestamp(),
                        "hostId": ""
                    ])
                }
            } catch {
                print("❌ Error during host cleanup: \(error)")
            }
        }
    }
    
    
    func setupVideoEndHandler(onVideoEnd: @escaping () -> Void) {
        print("🔄 Setting up video end handler...")

        // 1️⃣ Remove existing observer before adding a new one
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: currentPlayer?.currentItem
        )

        // 2️⃣ Add a new observer for when the video reaches the end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: currentPlayer?.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            
            print("🎬 Video ended, handling cleanup and state updates...")

            // 3️⃣ Update Firestore to mark video session as completed
            Task {
                if let syncRef = self.getBasePath() {
                    try? await syncRef.document("playState").updateData([
                        "isPlaying": false,
                        "playbackPosition": 0.0, // Reset position
                        "sessionEnded": true,
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                    print("✅ Firestore session marked as completed.")
                }
            }

            // 4️⃣ Store last known playback position (useful for replay feature)
            if let player = self.currentPlayer {
                let lastPosition = player.currentTime().seconds
                print("📍 Storing last playback position: \(lastPosition)")
                self.currentSnapshot = SyncSnapshot(position: lastPosition, isPlaying: false)
            }

            // 5️⃣ Cleanup playback and notify UI to handle transitions
            self.handlePlayPause(isPlaying: false)
            self.cleanup()
            
            DispatchQueue.main.async {
                onVideoEnd() // Notify UI to transition user away
            }
        }
        print("✅ Video end handler setup complete.")
    }

}
