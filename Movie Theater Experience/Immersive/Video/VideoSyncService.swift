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

@Observable
class VideoSyncService {
    // MARK: - Public / Observable
    var isHost = false
    var isWithinEventTime = false
    var lastError: Error?
    var currentTime = 0.0
    
    // MARK: - Private
    private let db: Firestore
    
    /// The *actual* player we are syncing with.
    /// We keep it here so we can remove the time observer from
    /// this exact instance in `cleanup()`.
    private(set) var currentPlayer: AVPlayer?
    
    private var timeObserverToken: Any?
    private var isPlayingState = false
    
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
        guard isWithinEventTime else { return }
        
        // 1) Remove old observer if needed
        removeTimeObserverIfNeeded()
        
        // 2) Set the new player
        self.currentPlayer = newPlayer
        
        // 3) Add a time observer on newPlayer
        setupTimeObservation(newPlayer)
        
        // 4) Setup playState listeners in Firestore
        setupVideoSync()
        
        print("🔄 Player synced with VideoSyncService")
    }
    
    func handleVideoEnd() {
        print("❌ Handling video end, stopping playback, cleaning up")
        
        handlePlayPause(isPlaying: false)
        cleanup()
    }
    
    
    func handlePlayPause(isPlaying: Bool) {
        guard isHost,
              isWithinEventTime,
              let syncRef = getBasePath(),
              isPlayingState != isPlaying else { return }
        
        isPlayingState = isPlaying
        
        // Update local player
        if isPlaying {
            currentPlayer?.play()
        } else {
            currentPlayer?.pause()
        }
        
        // Update Firebase
        syncRef.document("playState").setData([
            "isPlaying": isPlaying,
            "timestamp": currentPlayer?.currentTime().seconds ?? 0,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": UUID().uuidString
        ], merge: true)
    }
    
    private func cleanupListeners() {
          listeners.forEach { $0?.remove() }
          listeners.removeAll()
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
        if let token = timeObserverToken,
           let oldPlayer = currentPlayer {
            print("Removing old time observer from old player instance")
            oldPlayer.removeTimeObserver(token)
        }
        timeObserverToken = nil
        currentPlayer = nil
    }
    
    
    // MARK: - Add a periodic time observer
    private func setupTimeObservation(_ player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        // Add observer
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds  // This updates our published currentTime property
            
            // If we're the host, push timestamps to Firestore
            if self.isHost {
                guard let syncRef = self.getBasePath() else { return }
                syncRef.document("playState").updateData([
                    "timestamp": time.seconds,
                    "updatedAt": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                        print("❌ Failed to update timestamp: \(error)")
                    }
                }
            }
        }
    }
    

    private func cleanupTimers() {
        timers.forEach { $0?.invalidate() }
        timers.removeAll()
    }
    
    func cleanup() {
            print("=== VideoSyncService cleanup ===")
            
            // 1) Remove time observer from current player
            removeTimeObserverIfNeeded()
            
            // 2) Remove notification observers
            NotificationCenter.default.removeObserver(self)
            
            Task {
                // 3) Ensure host is cleaned up first
                await ensureHostCleanup()
                
                // 4) Clean up presence from DB
                if let eid = eventId, let uid = userId {
                    await cleanupDatabasePresence(eventId: eid, userId: uid)
                }
                
                // 5) Remove all listeners
                cleanupListeners()
                
                // 6) Stop timers
                cleanupTimers()
                
                // 7) Reset local state
                isHost = false
                isWithinEventTime = false
                eventId = nil
                userId = nil
                event = nil
                isPlayingState = false
                
                print("✅ VideoSyncService cleanup complete")
            }
        }
    
    // MARK: - Private Setup Methods
    private func initializeRoom() async {
        guard let syncRef = getBasePath() else { return }
        
        do {
            // Check if room is empty
            let activeViewers = try await syncRef.document("presence")
                .collection("activeViewers")
                .getDocuments()
            
            if activeViewers.isEmpty {
                try await createInitialRoomState(in: syncRef)
                await becomeHost()
            }
            
            // Register presence
            await registerPresence()
            
        } catch {
            handleError(error)
        }
    }
    
    func handleAppTermination() {
        // Force immediate cleanup
        Task {
            await ensureHostCleanup()
            cleanup()
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        VideoSyncService.shared.handleAppTermination()
    }
    
    private func setupVideoSync() {
        guard let syncRef = getBasePath() else { return }
        let playStateListener = syncRef.document("playState")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                guard let data = snapshot?.data(),
                      let serverTimestamp = data["timestamp"] as? Double,
                      let isPlaying = data["isPlaying"] as? Bool else {
                    return
                }
                
                // If I'm not the host, follow the server state
                if !self.isHost {
                    self.handleServerPlayState(isPlaying: isPlaying, timestamp: serverTimestamp)
                }
            }
        listeners.append(playStateListener)
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
        guard let eventId = eventId else {
            handleError(VideoSyncError.missingEventId)
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd-yyyy"
        let dateString = dateFormatter.string(from: Date())
        
        return db.collection("Public Rooms/\(dateString)/Events/\(eventId)/sync")
    }
    
    private func handleServerPlayState(isPlaying: Bool, timestamp: Double) {
        guard let player = currentPlayer else { return }
        
        let playerIsPlaying = (player.timeControlStatus == .playing)
        if playerIsPlaying != isPlaying {
            if isPlaying { player.play() } else { player.pause() }
        }
        
        let currentTime = player.currentTime().seconds
        if abs(currentTime - timestamp) > syncThreshold {
            player.seek(to: CMTime(seconds: timestamp, preferredTimescale: 1000))
        }
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
        isHost = false
        isWithinEventTime = false
        isPlayingState = false
        currentPlayer = nil
        eventId = nil
        userId = nil
        event = nil
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
            "timestamp": FieldValue.serverTimestamp(),
            "lastActive": FieldValue.serverTimestamp(),
            "status": "active"
        ], forDocument: hostDoc)
        
        // Play state document
        let playStateDoc = syncRef.document("playState")
        batch.setData([
            "isPlaying": true,
            "timestamp": 0.0,
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
    
    private func initiateHostElection() async {
        guard let syncRef = getBasePath() else { return }
        
        do {
            let viewers = try await syncRef.document("presence")
                .collection("activeViewers")
                .order(by: "lastSeen", descending: false)
                .limit(to: 1)
                .getDocuments()
            
            if let firstViewer = viewers.documents.first,
               firstViewer.documentID == userId {
                await becomeHost()
            }
        } catch {
            handleError(error)
        }
    }
    
    private func becomeHost() async {
        guard let syncRef = getBasePath() else { return }
        print("Becoming host...")
        
        do {
            // Update host document
            try await syncRef.document("host").setData([
                "hostId": userId ?? "",
                "timestamp": FieldValue.serverTimestamp(),
                "lastActive": FieldValue.serverTimestamp(),
                "status": "active"
            ])
            
            // Update local state
            isHost = true
            
            // Update room state
            try await syncRef.document("state").updateData([
                "lastHostChange": FieldValue.serverTimestamp(),
                "currentHost": userId ?? ""
            ])
            
            print("✅ Successfully became host")
        } catch {
            handleError(error)
            isHost = false
        }
    }
}

// MARK: - Presence Management
extension VideoSyncService {
    private func registerPresence() async {
        guard let syncRef = getBasePath() else { return }
        
        do {
            // Add to active viewers
            let viewerRef = syncRef.document("presence")
                .collection("activeViewers")
                .document(userId ?? "")
            
            try await viewerRef.setData([
                "userId": userId ?? "",
                "lastSeen": FieldValue.serverTimestamp(),
                "joined": FieldValue.serverTimestamp(),
                "status": "active"
            ])
            
            // Setup host listener after registering presence
            setupHostListener()
            setupPresenceListener()

        } catch {
            handleError(error)
        }
    }
    
    private func updatePresence() async {
        guard let syncRef = getBasePath() else { return }
        
        do {
            // Update active viewer status using the currentTime property
            // that's being updated by the periodic time observer
            try await syncRef.document("presence")
                .collection("activeViewers")
                .document(userId ?? "")
                .updateData([
                    "lastSeen": FieldValue.serverTimestamp(),
                    "timestamp": currentTime,  // Use the currentTime property instead of accessing player directly
                    "isHost": isHost
                ])
            
            // Update host status if needed
            if isHost {
                try await syncRef.document("host").updateData([
                    "lastActive": FieldValue.serverTimestamp()
                ])
            }
        } catch {
            handleError(error)
        }
    }

    
    private func cleanupDatabasePresence(eventId: String, userId: String) async {
        print("🧹 Starting database cleanup...")
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MM-dd-yyyy"
        let dateString = dateFormatter.string(from: Date())
        
        let path = "Public Rooms/\(dateString)/Events/\(eventId)/sync"
        let syncRef = db.collection(path)
        
        do {
            // Update historical viewer record
            let historicalViewerRef = syncRef.document("presence")
                .collection("historicalViewers")
                .document(userId)
            
            try await historicalViewerRef.updateData([
                "lastSeen": FieldValue.serverTimestamp(),
                "watchTime": FieldValue.increment(Date().timeIntervalSince(joinTime)),
                "completedViewing": true
            ])
            
            // Remove from active viewers
            try await syncRef.document("presence")
                .collection("activeViewers")
                .document(userId)
                .delete()
            
            // If we're the host, handle host cleanup
            if isHost {
                try await handleHostCleanup(syncRef)
            }
            
            print("✅ Database cleanup completed")
        } catch {
            print("❌ Database cleanup error: \(error.localizedDescription)")
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
        // Remove any existing observers
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: currentPlayer?.currentItem
        )
        
        // Add new observer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: currentPlayer?.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            
            // Stop playback and cleanup
            self.handlePlayPause(isPlaying: false)
            self.cleanup()
            
            // Execute completion handler
            DispatchQueue.main.async {
                onVideoEnd()
            }
        }
    }
}
