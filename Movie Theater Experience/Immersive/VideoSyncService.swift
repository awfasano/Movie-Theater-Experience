import Foundation
import FirebaseFirestore
import FirebaseCore
import FirebaseCrashlytics
import AVFoundation
import Combine

enum FirestoreError: Error {
    case missingDatabase
    case missingEventId
    case invalidPath(String)
    case firestoreError(String)
    case unknown
}

@Observable
class VideoSyncService: ObservableObject {
    
    
    // MARK: - Published Properties
    var currentTimestamp: Double = 0
    var isHost: Bool = false
    var isWithinEventTime: Bool = false
    var lastError: Error?

    // MARK: - Private Properties
    private let db: Firestore
    private var event: CalendarEvent?
    private weak var player: AVPlayer?
    
    // Firestore listeners
    private var listener: ListenerRegistration?
    private var hostListener: ListenerRegistration?
    private var presenceListener: ListenerRegistration?
    private var playStateListener: ListenerRegistration?
    private var joinTime: Date = Date()

    // Timers
    private var syncTimer: Timer?
    private var eventMonitorTimer: Timer?
    
    // Reference properties
    private var eventId: String?
    private var userId: String?
    private var hostPresenceRef: DocumentReference?
    
    private var isInitializing: Bool = false
    private let initializationLock = NSLock()
    
    // Constants
    private let syncThreshold: Double = 3.0
    private let syncInterval: TimeInterval = 2.0
    private let presenceUpdateInterval: TimeInterval = 10.0
    
    // MARK: - Initialization
    static let shared = VideoSyncService()  // Add a shared instance
    
    private init() {
        self.db = Firestore.firestore(database: "movieexperiencedb")
            print("📝 Database initialized: \(self.db)")
    }
    
    // MARK: - Public Methods
    func configureSync(eventId: String, userId: String, event: CalendarEvent) -> Bool {
        print("=== Configuring Sync Service ===")
        print("Event ID: \(eventId)")
        print("User ID: \(userId)")
        print("Event Start: \(event.date)")
        print("Event End: \(event.end)")
                
        // Validate inputs
        guard !eventId.isEmpty else {
            handleError(FirestoreError.missingEventId)
            return false
        }
        guard !userId.isEmpty else {
            handleError(FirestoreError.firestoreError("User ID is empty."))
            return false
        }
        
        self.joinTime = Date()
        self.event = event
        self.eventId = eventId
        self.userId = userId
        
        updateEventTimeStatus()
        guard isWithinEventTime else {
            print("Cannot configure sync: Outside event time window")
            return false
        }
        
        // Make sure initialization happens in order
        Task {
            do {
                print("📝 Starting sync initialization...")
                
                // First check and handle empty room
                await checkAndHandleEmptyRoom()
                
                // Create documents if needed
                await createInitialSyncDocuments()
                
                // Setup listeners
                setupHostListener()
                await registerPresence()
                
                // Start timers
                startPresenceTimer()
                startEventTimeMonitoring()
                
                print("✅ Sync initialization completed")
            } catch {
                print("❌ Error during sync initialization: \(error)")
                handleError(error)
            }
        }
        
        print("Sync service configured successfully")
        return true
    }
    
    private func handleError(_ error: Error) {
        print("Received error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.lastError = error
        }
    }
    
    func startSync(with player: AVPlayer) {
        print("Starting video sync")
        
        guard isWithinEventTime else {
            handleError(FirestoreError.firestoreError("Attempted to start sync outside the event time window."))
            return
        }
        
        guard let event = event else {
            handleError(FirestoreError.firestoreError("No event data found. Cannot start sync."))
            return
        }
        
        self.player = player
        
        Task {
            do {
                guard let syncRef = getBasePath() else { return }
                
                // First check for host
                let hostDoc = try await syncRef.document("host").getDocument()
                
                if !hostDoc.exists {
                    print("No host exists, starting from beginning")
                    player.seek(to: .zero) { [weak self] finished in
                        if finished {
                            print("Initial seek to beginning completed")
                        }
                    }
                } else {
                    let now = Date()
                    let elapsedTime = now.timeIntervalSince(event.date)
                    print("Host exists, setting elapsed time position: \(elapsedTime)")
                    let targetTime = CMTime(seconds: elapsedTime, preferredTimescale: 1000)
                    
                    player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                        if finished {
                            print("Initial seek completed")
                            if self?.isHost == true {
                                print("Host starting playback")
                                player.play()
                                self?.handlePlayPause(isPlaying: true)
                                self?.performSync()
                                self?.startSyncTimer()
                            }
                        }
                    }
                }
                
                startTimingListener()
                startPlayStateListener()
                
            } catch {
                print("Error during sync initialization: \(error.localizedDescription)")
            }
        }
    }

    
    func handlePlayPause(isPlaying: Bool) {
        guard isHost, isWithinEventTime,
              let syncRef = getBasePath() else {
            print("Cannot handle play/pause: Invalid state or missing data - isHost: \(isHost), isWithinTime: \(isWithinEventTime)")
            return
        }
        
        print("Host handling play/pause: \(isPlaying)")
        
        // Ensure local player state
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
        
        // Then update Firestore
        syncRef.document("playState").setData([
            "isPlaying": isPlaying,
            "timestamp": player?.currentTime().seconds ?? 0,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("Error updating play state: \(error)")
                // Surface error
                self.handleError(FirestoreError.firestoreError(error.localizedDescription))
            } else {
                print("Play state successfully updated to: \(isPlaying)")
            }
        }
    }

    
    func stopSync() {
        print("Stopping video sync")
        syncTimer?.invalidate()
        syncTimer = nil
        eventMonitorTimer?.invalidate()
        eventMonitorTimer = nil
        listener?.remove()
        listener = nil
        hostListener?.remove()
        hostListener = nil
        playStateListener?.remove()
        playStateListener = nil
        removePresence()
        player = nil
    }
    
    // MARK: - Private Methods
    private func getBasePath() -> CollectionReference? {
        
        guard let eventId = eventId else {
            print("❌ Missing event ID")
            handleError(FirestoreError.missingEventId)
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MM-dd-yyyy"
        let dateString = dateFormatter.string(from: Date())
        
        let path = "Public Rooms/\(dateString)/Events/\(eventId)/sync"
        print("📝 Constructed Firestore path: \(path)")
        
        // Verify path components
        print("📝 Path components:")
        print("- Base: Public Rooms")
        print("- Date: \(dateString)")
        print("- Event ID: \(eventId)")
        
        return db.collection(path)
    }
    
    private func lockInitialization() {
        initializationLock.lock()
        isInitializing = true
    }
    
    private func unlockInitialization() {
        isInitializing = false
        initializationLock.unlock()
    }

    
    private func createInitialSyncDocuments() {
        guard let syncRef = getBasePath() else {
            print("❌ Cannot create sync documents: Invalid path")
            return
        }
        
        print("📝 Starting creation of initial sync documents at path: \(syncRef.path)")
        
        Task {
            do {
                // Create presence document first with better error handling
                print("📝 Creating presence document...")
                let presenceRef = syncRef.document("presence")
                try await presenceRef.setData([
                    "activeViewerCount": 0,
                    "lastUpdated": FieldValue.serverTimestamp()
                ])
                print("✅ Presence document created successfully")
                
                // Create host document with explicit error handling
                print("📝 Creating host document...")
                try await syncRef.document("host").setData([
                    "hostId": "",
                    "timestamp": FieldValue.serverTimestamp(),
                    "lastActive": FieldValue.serverTimestamp()
                ])
                print("✅ Host document created successfully")
                
                // Create play state
                print("📝 Creating play state document...")
                try await syncRef.document("playState").setData([
                    "isPlaying": false,
                    "timestamp": 0.0,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                print("✅ Play state document created successfully")
                
                // Create timing document
                print("📝 Creating timing document...")
                try await syncRef.document("timing").setData([
                    "timestamp": 0.0,
                    "updatedAt": FieldValue.serverTimestamp(),
                    "currentPosition": 0.0
                ])
                print("✅ Timing document created successfully")
                
                // Create state document
                print("📝 Creating state document...")
                try await syncRef.document("state").setData([
                    "currentUsers": [],
                    "lastUpdated": FieldValue.serverTimestamp(),
                    "status": "active"
                ])
                print("✅ State document created successfully")
                
                print("✅ All initial sync documents created successfully")
                
                // Verify documents were created
                for docName in ["presence", "host", "playState", "timing", "state"] {
                    let docSnapshot = try await syncRef.document(docName).getDocument()
                    if docSnapshot.exists {
                        print("✅ Verified \(docName) document exists")
                    } else {
                        print("❌ Failed to verify \(docName) document")
                    }
                }
                
                await becomeHost()
                
            } catch {
                print("❌ Error creating sync documents: \(error.localizedDescription)")
                handleError(FirestoreError.firestoreError(error.localizedDescription))
            }
        }
    }
    
    private func updateEventTimeStatus() {
        guard let event = event else {
            print("Cannot update event time status: No event")
            isWithinEventTime = false
            return
        }
        
        let now = Date()
        isWithinEventTime = now >= event.date && now <= event.end
        
        print("""
        Event time status:
        Current time: \(now)
        Event start: \(event.date)
        Event end: \(event.end)
        Within time window: \(isWithinEventTime)
        """)
        
        if !isWithinEventTime {
            player?.pause()
        }
    }

    private func setupHostListener() {
        guard let syncRef = getBasePath() else {
            print("Cannot setup host listener: Invalid path")
            return
        }
        
        hostListener = syncRef.document("host").addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.handleError(FirestoreError.firestoreError(error.localizedDescription))
                return
            }
            
            guard let data = snapshot?.data() else {
                // If snapshot is nil or no data
                print("No host data, initiating election")
                self.initiateHostElection()
                return
            }
            
            if let hostId = data["hostId"] as? String {
                let wasHost = self.isHost
                self.isHost = (hostId == self.userId)
                print("Host status updated - is host: \(self.isHost)")
                
                if wasHost != self.isHost {
                    print("Host transition occurred, maintaining current playback state")
                }
            } else {
                print("No host data, initiating election")
                self.initiateHostElection()
            }
        }
    }

    
    private func initiateHostElection() {
        guard let syncRef = getBasePath() else {
            print("Cannot initiate host election: Invalid path")
            return
        }
        
        print("Initiating host election")
        
        let presenceQuery = syncRef.document("presence")
            .collection("users")
            .order(by: "lastSeen", descending: false)
            .limit(to: 1)
        
        // Create Task to handle async operations
        Task {
            do {
                let snapshot = try await presenceQuery.getDocuments()
                
                guard let firstDoc = snapshot.documents.first,
                      firstDoc.documentID == self.userId else {
                    print("Not eligible for host or error in election")
                    return
                }
                
                print("Won election, becoming host")
                await becomeHost()
                
            } catch {
                self.handleError(FirestoreError.firestoreError(error.localizedDescription))
            }
        }
    }

    
    private func becomeHost() async {
        guard let syncRef = getBasePath() else {
            print("❌ Cannot become host: Invalid path")
            return
        }
        
        print("📝 Attempting to become host...")
        
        do {
            // Update host document with retry logic
            let maxRetries = 3
            var retryCount = 0
            var success = false
            
            while !success && retryCount < maxRetries {
                do {
                    try await syncRef.document("host").setData([
                        "hostId": userId ?? "",
                        "timestamp": FieldValue.serverTimestamp(),
                        "lastActive": FieldValue.serverTimestamp(),
                        "status": "active"
                    ])
                    success = true
                    print("✅ Host document updated successfully")
                } catch {
                    retryCount += 1
                    print("⚠️ Retry \(retryCount)/\(maxRetries) updating host document: \(error.localizedDescription)")
                    if retryCount < maxRetries {
                        try await Task.sleep(nanoseconds: UInt64(0.5 * Double(NSEC_PER_SEC)))
                    }
                }
            }
            
            guard success else {
                print("❌ Failed to update host document after \(maxRetries) attempts")
                return
            }
            
            // Update local state
            self.isHost = true
            print("✅ Local host state updated")
            
            // Update state document
            try await syncRef.document("state").updateData([
                "lastHostChange": FieldValue.serverTimestamp(),
                "currentHost": userId ?? ""
            ])
            print("✅ State document updated")
            
            // Initialize playback state
            if let player = self.player {
                print("📝 Initializing playback state...")
                player.seek(to: .zero) { [weak self] finished in
                    if finished {
                        print("✅ Initial seek completed")
                        player.play()
                        self?.handlePlayPause(isPlaying: true)
                    }
                }
                
                // Update playState
                try await syncRef.document("playState").setData([
                    "isPlaying": true,
                    "timestamp": 0.0,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                print("✅ Play state initialized")
            }
            
            print("✅ Successfully became host")
            
        } catch {
            print("❌ Error becoming host: \(error.localizedDescription)")
            self.isHost = false
            handleError(FirestoreError.firestoreError(error.localizedDescription))
        }
    }

    
    private func registerPresence() {
        guard let syncRef = getBasePath() else {
            print("Cannot register presence: Invalid path")
            return
        }
        
        Task {
            do {
                // Ensure presence document exists
                try await syncRef.document("presence").setData([:], merge: true)
                
                let activeViewerRef = syncRef.document("presence")
                    .collection("activeViewers")
                    .document(userId ?? "")
                
                let historicalViewerRef = syncRef.document("presence")
                    .collection("historicalViewers")
                    .document(userId ?? "")
                
                self.hostPresenceRef = activeViewerRef
                
                // Create active viewer document
                try await activeViewerRef.setData([
                    "userId": userId ?? "",
                    "lastSeen": FieldValue.serverTimestamp(),
                    "timestamp": player?.currentTime().seconds ?? 0,
                    "joined": FieldValue.serverTimestamp()
                ])
                
                // Create historical viewer document
                try await historicalViewerRef.setData([
                    "userId": userId ?? "",
                    "firstJoined": FieldValue.serverTimestamp(),
                    "lastSeen": FieldValue.serverTimestamp(),
                    "watchTime": 0
                ], merge: true)
                
                await updatePresence()
                setupPresenceListener()
                
            } catch {
                handleError(FirestoreError.firestoreError(error.localizedDescription))
            }
        }
    }
    
    private func updatePresence() async {
        guard let hostPresenceRef = hostPresenceRef,
              let syncRef = getBasePath() else {
            print("Cannot update presence: No presence reference")
            return
        }
        
        do {
            // Update active viewer document
            try await hostPresenceRef.setData([
                "userId": userId ?? "",
                "lastSeen": FieldValue.serverTimestamp(),
                "timestamp": player?.currentTime().seconds ?? 0,
                "isHost": isHost,
                "status": "active"
            ], merge: true)
            
            // Update state document
            try await syncRef.document("state").updateData([
                "lastUpdated": FieldValue.serverTimestamp()
            ])
            
            if isHost {
                // Update host document
                try await syncRef.document("host").updateData([
                    "lastActive": FieldValue.serverTimestamp()
                ])
            }
        } catch {
            handleError(FirestoreError.firestoreError(error.localizedDescription))
        }
    }
    
    private func setupPresenceListener() {
        guard let syncRef = getBasePath() else {
            print("Cannot setup presence listener: Invalid path")
            return
        }
        
        let activeViewersQuery = syncRef.document("presence")
            .collection("activeViewers")
            .order(by: "lastSeen", descending: false)
        
        presenceListener = activeViewersQuery.addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.handleError(FirestoreError.firestoreError(error.localizedDescription))
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("No documents in presence listener.")
                return
            }
            
            let activeViewers = documents.filter { doc in
                if let lastSeen = doc.data()["lastSeen"] as? Timestamp {
                    let thirtySecondsAgo = Date().addingTimeInterval(-30)
                    return lastSeen.dateValue() > thirtySecondsAgo
                }
                return false
            }
            
            print("Active viewers: \(activeViewers.count)")
            
            if !activeViewers.isEmpty {
                Task {
                    await self.handleHostElectionIfNeeded(activeViewers)
                }
            }
        }
    }

    
    private func handleHostElectionIfNeeded(_ presenceDocs: [QueryDocumentSnapshot]) async {
        guard !isHost,
              let userId = userId,
              let firstPresent = presenceDocs.first,
              firstPresent.documentID == userId else {
            return
        }
        
        await becomeHost()
    }

    private func startPresenceTimer() {
        Timer.scheduledTimer(withTimeInterval: presenceUpdateInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.updatePresence()
            }
        }
    }
    
    private func removePresence() {
        guard let syncRef = getBasePath() else { return }
        
        // Historical viewer record
        let historicalViewerRef = syncRef.document("presence")
            .collection("historicalViewers")
            .document(userId ?? "")
        
        historicalViewerRef.updateData([
            "lastSeen": FieldValue.serverTimestamp(),
            "watchTime": FieldValue.increment(Date().timeIntervalSince(joinTime))
        ]) { [weak self] error in
            if let error = error {
                self?.handleError(FirestoreError.firestoreError(error.localizedDescription))
            }
        }
        
        // Remove from active viewers
        hostPresenceRef?.delete { [weak self] error in
            if let error = error {
                self?.handleError(FirestoreError.firestoreError(error.localizedDescription))
            }
        }
        
        presenceListener?.remove()
    }

    
    private func startSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            self?.performSync()
        }
    }
    
    private func startEventTimeMonitoring() {
        eventMonitorTimer?.invalidate()
        eventMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let wasWithinTime = self.isWithinEventTime
            self.updateEventTimeStatus()
            
            if wasWithinTime && !self.isWithinEventTime {
                self.stopSync()
            }
        }
    }
    
    private func verifyBatchWrite(syncRef: CollectionReference) async throws {
        print("📝 Verifying batch write results...")
        
        let snapshot = try await syncRef.getDocuments()
        print("📝 Found \(snapshot.documents.count) documents")
        
        // Create a set of expected document IDs
        let expectedDocs = Set(["presence", "host", "playState", "timing", "state"])
        let foundDocs = Set(snapshot.documents.map { $0.documentID })
        
        // Print what we found
        print("📝 Found documents: \(foundDocs.joined(separator: ", "))")
        print("📝 Missing documents: \(expectedDocs.subtracting(foundDocs).joined(separator: ", "))")
        
        // Verify each document's contents
        for docName in expectedDocs {
            let docRef = syncRef.document(docName)
            let docSnapshot = try await docRef.getDocument()
            
            if docSnapshot.exists {
                print("✅ Verified \(docName) document exists with data: \(docSnapshot.data() ?? [:])")
            } else {
                print("❌ Failed to verify \(docName) document")
                throw FirestoreError.firestoreError("Document \(docName) was not created")
            }
        }
    }

    
    private func startTimingListener() {
        guard let syncRef = getBasePath() else {
            print("Cannot start timing listener: Invalid path")
            return
        }
        
        listener = syncRef.document("timing").addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.handleError(FirestoreError.firestoreError(error.localizedDescription))
                return
            }
            
            // Only sync if not host & within event time
            guard !self.isHost,
                  self.isWithinEventTime,
                  let data = snapshot?.data(),
                  let serverTimestamp = data["timestamp"] as? Double else {
                return
            }
            
            self.handleServerSync(serverTimestamp: serverTimestamp)
        }
    }

    
    private func startPlayStateListener() {
            guard let syncRef = getBasePath() else {
                print("Cannot start play state listener: Invalid path")
                return
            }
            
            print("Starting play state listener")
            
            playStateListener = syncRef.document("playState").addSnapshotListener { [weak self] (snapshot, error) in
                guard let self = self,
                      !self.isInitializing else { // Check initialization state
                    print("Ignoring play state update during initialization")
                    return
                }
                
                if let error = error {
                    self.handleError(FirestoreError.firestoreError(error.localizedDescription))
                    return
                }
                
                guard !self.isHost,
                      self.isWithinEventTime,
                      let data = snapshot?.data(),
                      let isPlaying = data["isPlaying"] as? Bool,
                      let player = self.player else {
                    print("Play state update guard failed...")
                    return
                }
                
                print("Updating player state to: \(isPlaying)")
                if isPlaying {
                    player.play()
                } else {
                    player.pause()
                }
            }
        }
    
    private func checkAndHandleEmptyRoom() async {
        guard let syncRef = getBasePath() else {
            print("❌ Cannot check empty room: Invalid path")
            return
        }
        
        print("📝 Checking room status...")
        
        do {
            // First check if sync documents exist
            let documents = try await syncRef.getDocuments()
            let documentsExist = !documents.isEmpty
            
            print("📝 Documents exist: \(documentsExist)")
            
            // Check active viewers
            let activeViewersSnapshot = try await syncRef.document("presence")
                .collection("activeViewers")
                .getDocuments()
            
            let activeViewerCount = activeViewersSnapshot.documents.filter { doc in
                if let lastSeen = doc.data()["lastSeen"] as? Timestamp {
                    let thirtySecondsAgo = Date().addingTimeInterval(-30)
                    return lastSeen.dateValue() > thirtySecondsAgo
                }
                return false
            }.count
            
            print("📝 Active viewer count: \(activeViewerCount)")
            
            if activeViewerCount == 0 {
                print("📝 Room is empty, initializing as first viewer")
                
                // Create initial documents in a specific order
                try await initializeEmptyRoom(syncRef)
                
                // Register presence first
                print("📝 Registering initial presence...")
                await registerPresence()
                
                // Then become host
                print("📝 Becoming initial host...")
                await becomeHost()
                
                print("✅ Room initialized successfully")
            }
        } catch {
            print("❌ Error handling empty room: \(error.localizedDescription)")
        }
    }

    private func initializeEmptyRoom(_ syncRef: CollectionReference) async throws {
        print("📝 Initializing empty room...")
        
        // First verify the parent document exists
        let parentPath = syncRef.parent
        if parentPath != nil {
            let parentDoc = try await parentPath!.getDocument()
            print("📝 Parent document exists: \(parentDoc.exists)")
            
            if !parentDoc.exists {
                throw FirestoreError.invalidPath("Parent document does not exist")
            }
        }
        
        // Create a new batch for the sync collection documents
        let batch = db.batch()
        print("📝 Creating sync documents in collection: \(syncRef.path)")
        
        // Print all document references we're about to create
        let docRefs = [
            "host": syncRef.document("host"),
            "playState": syncRef.document("playState"),
            "presence": syncRef.document("presence"),
            "timing": syncRef.document("timing"),
            "state": syncRef.document("state")
        ]
        
        docRefs.forEach { (name, ref) in
            print("📝 Will create document: \(ref.path)")
        }
        
        // Add all documents to the batch
        batch.setData([
            "hostId": userId ?? "",
            "timestamp": FieldValue.serverTimestamp(),
            "lastActive": FieldValue.serverTimestamp(),
            "status": "active"
        ], forDocument: docRefs["host"]!)
        
        batch.setData([
            "isPlaying": false,
            "timestamp": 0.0,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: docRefs["playState"]!)
        
        batch.setData([
            "activeViewerCount": 1,
            "lastUpdated": FieldValue.serverTimestamp()
        ], forDocument: docRefs["presence"]!)
        
        batch.setData([
            "timestamp": 0.0,
            "updatedAt": FieldValue.serverTimestamp(),
            "currentPosition": 0.0
        ], forDocument: docRefs["timing"]!)
        
        batch.setData([
            "currentUsers": [userId ?? ""],
            "lastUpdated": FieldValue.serverTimestamp(),
            "status": "active"
        ], forDocument: docRefs["state"]!)
        
        // Try to commit with retry logic
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                print("📝 Attempting batch commit (attempt \(attempt)/\(maxRetries))...")
                try await batch.commit()
                
                // Verify the write by checking one document
                let verifyDoc = try await docRefs["host"]!.getDocument()
                if verifyDoc.exists {
                    print("✅ Batch commit verified successful")
                    return
                } else {
                    throw FirestoreError.firestoreError("Batch commit succeeded but documents not created")
                }
                
            } catch {
                lastError = error
                print("⚠️ Batch commit failed (attempt \(attempt)): \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    let delay = Double(attempt) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * Double(NSEC_PER_SEC)))
                }
            }
        }
        
        // If we get here, all retries failed
        throw lastError ?? FirestoreError.firestoreError("Batch commit failed after \(maxRetries) attempts")
    }
    
    private func verifyDocument(_ docRef: DocumentReference) async throws -> Bool {
        do {
            let snapshot = try await docRef.getDocument()
            return snapshot.exists
        } catch {
            print("⚠️ Error verifying document: \(error.localizedDescription)")
            return false
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * Double(NSEC_PER_SEC)))
                throw TimeoutError(duration: seconds)
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func clearSyncDocuments(in syncRef: CollectionReference) async throws {
        print("Clearing existing sync documents")
        
        // Delete host document if it exists
        try await syncRef.document("host").delete()
        
        // Reset timing document
        try await syncRef.document("timing").setData([
            "timestamp": 0.0,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        // Reset play state
        try await syncRef.document("playState").setData([
            "isPlaying": false,
            "timestamp": 0.0,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        print("Sync documents cleared successfully")
    }

    
    private func handleServerSync(serverTimestamp: Double) {
        guard let player = player else { return }
        
        let currentTime = player.currentTime().seconds
        let diff = abs(currentTime - serverTimestamp)
        
        if diff > syncThreshold {
            print("Syncing to server time: \(serverTimestamp), current: \(currentTime)")
            let targetTime = CMTime(seconds: serverTimestamp, preferredTimescale: 1000)
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    
    private func performSync() {
        guard isHost,
              isWithinEventTime,
              let syncRef = getBasePath(),
              let player = player else {
            return
        }
        
        let currentTime = player.currentTime().seconds
        
        syncRef.document("timing").setData([
            "timestamp": currentTime,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            if let error = error {
                self?.handleError(FirestoreError.firestoreError(error.localizedDescription))
            }
        }
    }
    deinit {
        stopSync()
    }
}

extension FirestoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingDatabase:
            return "Database reference is missing or invalid."
        case .missingEventId:
            return "Event ID is missing."
        case .invalidPath(let path):
            return "Invalid Firestore path: \(path)"
        case .firestoreError(let message):
            return "Firestore operation failed: \(message)"
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

extension VideoSyncService {
    @MainActor
    func handleUserExit() {
        print("Handling user exit...")
        
        // First stop all sync operations
        stopSync()
        
        // Update historical viewer data and remove from active viewers
        Task {
            // Update historical viewer data
            if let syncRef = getBasePath(),
               let userId = userId {
                
                let historicalViewerRef = syncRef.document("presence")
                    .collection("historicalViewers")
                    .document(userId)
                
                do {
                    try await historicalViewerRef.updateData([
                        "lastSeen": FieldValue.serverTimestamp(),
                        "watchTime": FieldValue.increment(Date().timeIntervalSince(joinTime))
                    ])
                    print("Historical viewer data updated successfully")
                    
                    // If we're the host, handle host reassignment before removal
                    if isHost {
                        // Get all active viewers except current user
                        let activeViewersRef = syncRef.document("presence").collection("activeViewers")
                        let snapshot = try await activeViewersRef
                            .whereField("userId", isNotEqualTo: userId)
                            .order(by: "userId")
                            .order(by: "lastSeen", descending: false)
                            .limit(to: 1)
                            .getDocuments()
                        
                        if let nextHost = snapshot.documents.first {
                            // Update host document with new host
                            try await syncRef.document("host").setData([
                                "hostId": nextHost.data()["userId"] as? String ?? "",
                                "timestamp": FieldValue.serverTimestamp()
                            ])
                            print("Host reassigned successfully")
                        } else {
                            // No other active viewers, delete host document
                            try await syncRef.document("host").delete()
                            print("Host document removed - no active viewers")
                        }
                    }
                    
                    // Remove self from active viewers
                    try await syncRef.document("presence")
                        .collection("activeViewers")
                        .document(userId)
                        .delete()
                    print("Removed from active viewers successfully")
                    
                } catch {
                    print("Error during exit cleanup: \(error.localizedDescription)")
                }
            }
            
            // Reset all state
            isHost = false
            isWithinEventTime = false
            currentTimestamp = 0
            
            // Clear references
            eventId = nil
            userId = nil
            hostPresenceRef = nil
            event = nil
            player = nil
            
            // Remove listeners if they haven't been removed yet
            listener?.remove()
            listener = nil
            hostListener?.remove()
            hostListener = nil
            presenceListener?.remove()
            presenceListener = nil
            playStateListener?.remove()
            playStateListener = nil
            
            // Invalidate timers
            syncTimer?.invalidate()
            syncTimer = nil
            eventMonitorTimer?.invalidate()
            eventMonitorTimer = nil
            
            print("All references cleaned up successfully")
            print("User exit handled successfully")
        }
    }
}
