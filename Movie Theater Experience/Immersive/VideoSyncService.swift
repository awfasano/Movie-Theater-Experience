//
//  VideoSyncService.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/28/25.
//

import Foundation
import UIKit // For applicationWillTerminate if needed, otherwise remove
import FirebaseFirestore
import FirebaseCore
import AVFoundation
import Observation // Make sure to import Observation



enum VideoSyncError: Error, Equatable {
    case missingDatabase
    case missingEventId
    case invalidPath(String)
    case firestoreError(String)
    case playerNotReady
    case syncConfigurationFailed
    
    
    static func == (lhs: VideoSyncError, rhs: VideoSyncError) -> Bool {
        switch (lhs, rhs) {
        case (.missingDatabase, .missingDatabase): return true
        case (.missingEventId, .missingEventId): return true
        case (.playerNotReady, .playerNotReady): return true
        case (.syncConfigurationFailed, .syncConfigurationFailed): return true
        case (.invalidPath(let lVal), .invalidPath(let rVal)): return lVal == rVal // Example for associated value
        case (.firestoreError(let lVal), .firestoreError(let rVal)): return lVal == rVal // Example for associated value
        default:
            // This handles cases where one has an associated value and the other doesn't,
            // or they are different enum cases entirely.
            // To make this truly robust for all comparisons, you'd list all pairs.
            // However, for tests comparing simple cases like .syncConfigurationFailed, this is okay.
            // A simple way if you only care about the case type for associated values:
            // return String(describing: lhs) == String(describing: rhs) // Not ideal but works for case type
            return false // Fallback: different cases or unhandled associated value comparisons
        }
    }
}

enum CleanupLevel {
    case full    // Complete cleanup
    case partial // Maintain sync state but cleanup player
    case light   // Just cleanup current player
}

@Observable // Ensure updates to these properties are main-thread safe
class VideoSyncService {

    enum ViewState {
        case immersive
        case movieWindow
        case none
    }
    public struct SyncSnapshot {
        let position: Double
        let isPlaying: Bool
    }

    private(set) var currentSnapshot: SyncSnapshot?
    private(set) var currentViewState: ViewState = .none

    // --- MODIFIED SINGLETON AND MOCKING SETUP ---
    private static var MOCK_firestoreOverride: Firestore?
    private static var _sharedInstance: VideoSyncService? // Correct declaration
    private static var MOCK_emulatorSettings: (host: String, port: Int)? = nil // << --- ENSURE THIS IS DECLARED
    private static var MOCK_firestoreClientToUse: Firestore? = nil // This will hold the pre-configured emulator client

    var currentVideoDuration: Double = 0.0



    // This is the ONLY public way to get the shared instance.
    static var shared: VideoSyncService {
        if _sharedInstance == nil {
            // This path is hit if MOCK_prepareForTesting was not called (e.g., production app launch)
            // or after MOCK_finishTesting.
            print("ℹ️ VideoSyncService.shared: Creating new instance (MOCK_firestoreOverride will be checked by init).")
            _sharedInstance = VideoSyncService()
        }
        return _sharedInstance!
    }

    // Call this from your tests' setUpWithError
    static func MOCK_prepareForTesting(emulatorHost: String, emulatorPort: Int) {
        print("🧪 VideoSyncService.MOCK_prepareForTesting: Configuring Firestore client for emulator (\(emulatorHost):\(emulatorPort)).")
        let emulatorFirestore = Firestore.firestore() // Create a new Firestore instance
        let settings = emulatorFirestore.settings
        settings.host = "\(emulatorHost):\(emulatorPort)"
        settings.isSSLEnabled = false
        settings.isPersistenceEnabled = false
        emulatorFirestore.settings = settings
        
        MOCK_firestoreClientToUse = emulatorFirestore // Store the configured client
        
        _sharedInstance = nil // Ensure a new service instance is created by the next .shared access
        _sharedInstance = VideoSyncService() // Force immediate creation of VideoSyncService, which will use MOCK_firestoreClientToUse
        print("✅ VideoSyncService.MOCK_prepareForTesting: Singleton reset. New instance will use pre-configured emulator Firestore client.")
    }
    
    // Test helper to directly call the private checkEventTime() method
    // Useful for Test 21 (testEventTime_eventEnds_cleanupIsTriggered)
    @MainActor
    func checkEventTime_TEST_HELPER() {
        // This directly calls the private method for testing purposes.
        // It simulates what the eventTimer would do.
        print("🧪 TEST_HELPER: Manually calling checkEventTime()")
        self.checkEventTime()
    }

    // Test helper to directly call the private updateEventTimeStatus() method
    // Useful for Test 21 if you need to force an update and then check `isWithinEventTime`
    @MainActor
    func updateEventTimeStatus_TEST_HELPER() {
        print("🧪 TEST_HELPER: Manually calling updateEventTimeStatus()")
        self.updateEventTimeStatus()
    }

    // Test helper to get the current timeObserverToken
    // Useful for Test 24 (testCleanup_light...) and Test 25 (testSwitchToView...)
    func MOCK_getTimeObserverToken() -> Any? {
        print("🧪 TEST_HELPER: Accessing timeObserverToken")
        return self.timeObserverToken
    }

    // Test helper to inspect the internal listeners array (optional, for deeper verification)
    // Useful for Test 22 (testCleanup_full...)
    func MOCK_getInternalListenersArray() -> [ListenerRegistration?] {
        print("🧪 TEST_HELPER: Accessing internal listeners array (count: \(self.listeners.count))")
        return self.listeners
    }
    
    // Test helper to inspect the internal timers array (optional, for deeper verification)
    // Useful for Test 22 (testCleanup_full...)
    func MOCK_getInternalTimersArray() -> [Timer?] {
        print("🧪 TEST_HELPER: Accessing internal timers array (count: \(self.timers.count))")
        return self.timers
    }
    

    // Call this from your tests' tearDownWithError
    static func MOCK_finishTesting() {
        MOCK_firestoreOverride = nil
        _sharedInstance = nil // Allow the instance to be nil, so it's recreated on next .shared access
        print("🧹 VideoSyncService.MOCK_finishTesting: Singleton mock cleared and instance nilled.")
    }
    // --- END OF MODIFIED SINGLETON AND MOCKING SETUP ---
    
    // MARK: - Public / Observable
    var isHost = false
    var isWithinEventTime = false
    var lastError: Error?
    var isPlaying: Bool { isPlayingState }
    var currentTime: Double = 0.0
    var activeViewerCount: Int = 0

    var dismissWindow: ((String) -> Void)?
    var dismissImmersiveSpace: (() -> Void)?

    var isPlayingState = false
    let db: Firestore // Made non-optional
    private var lastPresenceUpdate: Date?
    // Assuming ImmersiveSpaceManager is a true singleton or otherwise handled
    private let spaceManager = ImmersiveSpaceManager.shared
    

    var currentPlayer: AVPlayer?
    private var timeObserverToken: Any?
    var isPlayStateListenerActive = false
    private var lastSyncUpdate: Date?
    var lastFirestorePlayStateUpdateId: String?

    private let joinTime = Date()
    
    var event: CalendarEvent? // Made these settable by configureSync
    var eventId: String?
    var userId: String?

    private var listeners: [ListenerRegistration?] = []
    private var timers: [Timer?] = []

    let syncThreshold = 3.0
    let presenceInterval = 10.0
    let playerReadyTimeout = 5.0


    // MARK: - Init
    private init() {
        if let mockClient = VideoSyncService.MOCK_firestoreClientToUse {
            self.db = mockClient // Directly use the pre-configured mock client
            print("🔥 VideoSyncService.init: Using MOCK_firestoreClientToUse (Emulator settings applied by MOCK_prepareForTesting). Host: \(self.db.settings.host)")
        } else {
            let productionFirestore = Firestore.firestore(database: "movieexperiencedb")
            let settings = productionFirestore.settings
            settings.isSSLEnabled = true
            productionFirestore.settings = settings
            self.db = productionFirestore
            print("🔥 VideoSyncService.init: Using REAL Firestore settings (MOCK_firestoreClientToUse was nil).")
        }
        print("🔥 VideoSyncService.init: 'db' instance is now set.")
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppTerminationNotification), name: UIApplication.willTerminateNotification, object: nil)
    }
    
    static func MOCK_resetSharedInstanceForTesting(emulatorHost: String, emulatorPort: Int, useMock: Bool = true) {
        if useMock {
            let mockFirestore = Firestore.firestore() // Create a new instance for the mock
            let settings = mockFirestore.settings
            settings.host = "\(emulatorHost):\(emulatorPort)"
            settings.isSSLEnabled = false
            settings.isPersistenceEnabled = false
            mockFirestore.settings = settings
            MOCK_firestoreOverride = mockFirestore // The static override variable
        } else {
            MOCK_firestoreOverride = nil
        }
        // Force re-creation of the shared instance.
        // The init() method will now see MOCK_firestoreOverride correctly set.
        _sharedInstance = VideoSyncService()
    }

    // MARK: - Public Methods
    func configureSync(eventId: String, userId: String, event: CalendarEvent) async -> Bool {
        // --- Added: Cleanup if eventId is changing ---
        if let oldEventId = self.eventId, oldEventId != eventId {
            print("🔄 VideoSyncService.configureSync: Event ID changed from \(oldEventId) to \(eventId). Performing full cleanup of old event resources.")
            await cleanup(level: .full) // Ensures old listeners/timers are gone before configuring for new event
        } else if self.eventId == eventId && self.userId == userId {
            // Reconfiguring for the *same* event and user.
            // Decide if a partial or full cleanup is needed, or just re-initialize.
            // For now, let's assume a fresh setup is desired even for a re-configure.
            print("🔄 VideoSyncService.configureSync: Re-configuring for the same event (\(eventId)). Performing full cleanup first.")
            await cleanup(level: .full)
        } else if self.eventId == eventId && self.userId != userId {
            // Same event, different user. This is a significant change.
            print("🔄 VideoSyncService.configureSync: Event ID \(eventId) is the same, but User ID changed from \(self.userId ?? "nil") to \(userId). Performing full cleanup.")
            await cleanup(level: .full)
        }
        // --- End Added ---

        print("⚙️ Configuring Sync for Event: \(eventId), User: \(userId)")
        
        // Reset state for configuration (critical after potential cleanup)
        await MainActor.run { // Update observable properties on main thread
            self.eventId = eventId
            self.userId = userId
            self.event = event
            self.isHost = false
            self.isPlayingState = false
            self.currentTime = 0.0
            self.activeViewerCount = 0
            self.currentSnapshot = nil // Clear snapshot on new sync config
            self.isPlayStateListenerActive = false // Ensure listeners are setup anew
            self.lastError = nil // Clear any previous errors
        }

        // Update event time (can be done async)
        await MainActor.run { self.updateEventTimeStatus() } // 1️⃣ Update the flag

        let inTime = await MainActor.run { self.isWithinEventTime } // 2️⃣ Read the flag

        guard inTime else { // 3️⃣ Guard on the Boolean
            print("❌ VideoSyncService.configureSync: Outside event time window for event \(eventId). Cannot sync.")
            await MainActor.run {
                self.lastError = VideoSyncError.syncConfigurationFailed
            }
            return false
        }

        // Initialize room state and presence (async Firestore operations)
        let roomInitialized = await initializeRoom() // Modified initializeRoom
        guard roomInitialized else {
            print("❌ VideoSyncService.configureSync: Failed to initialize room state for event \(eventId).")
            // lastError should be set by initializeRoom in case of failure
            // Ensure it's set if initializeRoom returns false without explicit error
            if await MainActor.run(body: { self.lastError }) == nil {
                 await MainActor.run { self.lastError = VideoSyncError.syncConfigurationFailed }
            }
            return false
        }

        // Start monitoring timers (presence, event time)
        // These are re-created because cleanupTimers() would have been called by cleanup(level:.full)
        startMonitoring()

        // Setup Firestore listeners *after* basic room init
        // These are re-created because cleanupListeners() would have been called by cleanup(level:.full)
        setupPresenceListener()
        setupHostListener()
        // setupVideoSync() (for playState) will be called by startSync when player is ready

        print("✅ VideoSyncService.configureSync: Successfully configured for Event: \(eventId), User: \(userId)")
        return true
    }



    // Should be called on MainActor as it deals with AVPlayer
    @MainActor
    func startSync(with newPlayer: AVPlayer) async {
        print("⏯️ VideoSyncService.startSync: Starting with player: \(newPlayer). isWithinEventTime: \(isWithinEventTime)")
        guard isWithinEventTime else {
            print("❌ VideoSyncService.startSync: Cannot sync - outside event time.")
            self.lastError = VideoSyncError.syncConfigurationFailed
            return
        }

        if let current = currentPlayer, current !== newPlayer {
            print("🧹 VideoSyncService.startSync: Player instance changed. Cleaning up observer for previous player.")
            removeTimeObserverIfNeeded(from: current)
        } else if let current = currentPlayer, current === newPlayer {
            print("⚠️ VideoSyncService.startSync: Called with the same player instance. Re-initializing sync process.")
            removeTimeObserverIfNeeded(from: current)
        }

        self.currentPlayer = newPlayer
        print("👉 VideoSyncService.startSync: New player instance set: \(String(describing: self.currentPlayer))")

        do {
            print("⏳ VideoSyncService.startSync: Calling withTimeout for waitForPlayerReady (timeout: \(playerReadyTimeout)s)...")
            try await withTimeout(seconds: playerReadyTimeout) {
                print("⏳ VideoSyncService.startSync [withTimeout]: Operation: Calling self.waitForPlayerReady for player: \(newPlayer)")
                try await self.waitForPlayerReady(player: newPlayer)
                print("✅ VideoSyncService.startSync [withTimeout]: Operation: self.waitForPlayerReady completed.")
            }
            print("✅ VideoSyncService.startSync: Player is ready (withTimeout and waitForPlayerReady succeeded).")
            self.lastError = nil
            await continueSync(with: newPlayer)
        } catch let timeoutError as TimeoutError {
            print("❌ VideoSyncService.startSync: Caught TimeoutError: \(timeoutError.localizedDescription)")
            self.lastError = timeoutError
            await cleanup(level: .light)
        } catch let specificError as VideoSyncError {
            print("❌ VideoSyncService.startSync: Caught VideoSyncError: \(specificError)")
            self.lastError = specificError
            await cleanup(level: .light)
        } catch {
            print("❌ VideoSyncService.startSync: Caught other error during player readiness: \(error) (\(error.localizedDescription)). Error type: \(type(of: error))")
            self.lastError = error
            await cleanup(level: .light)
        }
        print("🏁 VideoSyncService.startSync: Finished. lastError: \(String(describing: self.lastError))")
    }
    
    
    @MainActor
    func MOCK_TEST_initiateHostElection() async {
        print("🧪 MOCK_TEST_initiateHostElection: Test directly calling initiateHostElection.")
        await self.initiateHostElection()
    }
    
    // MARK: - Player-readiness utilities
    // MARK: - Wait until an AVPlayer reaches `.readyToPlay`
    @MainActor
    private func waitForPlayerReady(player: AVPlayer) async throws {
        print("⏳ waitForPlayerReady: Checking player: \(player), status: \(player.status.rawValue), item: \(String(describing: player.currentItem)), itemStatus: \(player.currentItem?.status.rawValue ?? -99)")

        // Check initial state directly
        if player.status == .readyToPlay && player.currentItem?.status == .readyToPlay {
            print("✅ waitForPlayerReady: Player and item already ready.")
            return
        }
        if player.status == .failed {
            print("❌ waitForPlayerReady: Player status is FAILED early. Error: \(player.error?.localizedDescription ?? "Unknown player error")")
            throw player.error ?? VideoSyncError.playerNotReady
        }
        guard let currentItem = player.currentItem else {
            print("❌ waitForPlayerReady: Player has no currentItem to observe.")
            throw VideoSyncError.playerNotReady // Or a more specific error like .missingPlayerItem
        }
        if currentItem.status == .failed {
            print("❌ waitForPlayerReady: Player item status is FAILED early. Error: \(currentItem.error?.localizedDescription ?? "Unknown item error")")
            throw currentItem.error ?? VideoSyncError.playerNotReady
        }

        // If we are here, at least one of them is not .readyToPlay (and not .failed yet)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var playerStatusObservation: NSKeyValueObservation?
            var itemStatusObservation: NSKeyValueObservation?

            let cleanupObservations = {
                playerStatusObservation?.invalidate()
                itemStatusObservation?.invalidate()
                playerStatusObservation = nil
                itemStatusObservation = nil
            }

            var hasResumed = false // Prevent resuming multiple times

            let checkReadinessAndResume = {
                // This check needs to be on the MainActor as it accesses player properties
                Task { @MainActor in
                    if !hasResumed && player.status == .readyToPlay && currentItem.status == .readyToPlay {
                        hasResumed = true
                        cleanupObservations()
                        print("✅ waitForPlayerReady: Both player and item are ready. Resuming.")
                        continuation.resume(returning: ())
                    } else if !hasResumed && (player.status == .failed || currentItem.status == .failed) {
                        hasResumed = true
                        cleanupObservations()
                        let error = player.error ?? currentItem.error ?? VideoSyncError.playerNotReady
                        print("❌ waitForPlayerReady: Player or item failed during observation. Error: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    } else {
                         print("⏳ waitForPlayerReady (KVO check): Player status \(player.status.rawValue), Item status \(currentItem.status.rawValue). Waiting...")
                    }
                }
            }

            playerStatusObservation = player.observe(\.status, options: [.new, .initial]) { _, _ in
                checkReadinessAndResume()
            }

            itemStatusObservation = currentItem.observe(\.status, options: [.new, .initial]) { _, _ in
                checkReadinessAndResume()
            }
            
            // Initial check in case states were met right after KVO setup but before first callback
            checkReadinessAndResume()
        }
    }

    
    private struct ContinuationGuard {
        private var didResume = false
        mutating func resume(_ cont: CheckedContinuation<Void, Error>, throwing error: Error) {
            guard !didResume else { return }
            didResume = true
            cont.resume(throwing: error)
        }
        mutating func resume(_ cont: CheckedContinuation<Void, Error>) {
            guard !didResume else { return }
            didResume = true
            cont.resume()
        }
    }
    
    
    
    // Helper class to manage KVO token lifecycle with async/await
    private class KVOObservationHolder: @unchecked Sendable {
        var observation: NSKeyValueObservation?
        init(observation: NSKeyValueObservation?) { self.observation = observation }
        func invalidate() { observation?.invalidate(); observation = nil }
        deinit { observation?.invalidate() }
    }

    @MainActor
    private func clearSnapshot() {
        if currentSnapshot != nil {
            print("🗑️ Clearing playback snapshot.")
            currentSnapshot = nil
        } else {
            print("ℹ️ No snapshot to clear.")
        }
    }

    
    // In VideoSyncService.swift

    @MainActor
    func forceSyncToHost() async {
        guard !isHost, let syncRef = getBasePath()?.document("playState") else {
            print("ℹ️ Not a non-host or no sync path, cannot force sync to host.")
            return
        }
        
        print("🔄 Forcing sync to host state...")
        do {
            let snapshot = try await syncRef.getDocument(source: .server) // Force server read
            guard let data = snapshot.data(),
                  let serverIsPlaying = data["isPlaying"] as? Bool,
                  let serverPosition = data["playbackPosition"] as? Double else {
                print("⚠️ Missing or invalid data in playState snapshot during force sync.")
                self.lastError = VideoSyncError.firestoreError("Invalid data on force sync")
                return
            }
            
            print("📥 [Force Sync] Received Firestore playState: isPlaying=\(serverIsPlaying), pos=\(String(format: "%.2f", serverPosition))")
            
            // Apply directly
            self.updateLocalPlayState(isPlaying: serverIsPlaying, position: serverPosition)
            self.handleServerPlayState(isPlaying: serverIsPlaying, seconds: serverPosition) // This handles player seek & play/pause

        } catch {
            print("❌ Error during force sync to host: \(error.localizedDescription)")
            self.lastError = VideoSyncError.firestoreError("Failed to fetch host state on force sync: \(error.localizedDescription)")
        }
    }
    
    
    // In VideoSyncService.swift

    @MainActor
    func handleSeek(to newPosition: Double) async {
        guard let player = currentPlayer else {
            print("⚠️ Cannot seek: No player.")
            return
        }
        print(" Seeking to \(newPosition)s")
        
        // 1. Seek the local player
        await player.seek(to: CMTime(seconds: newPosition, preferredTimescale: 1000),
                          toleranceBefore: .zero, toleranceAfter: .zero)
        
        // 2. Update local state immediately
        //    The time observer will also update this, but an immediate update can make UI feel more responsive.
        //    Be cautious if this causes issues with the time observer's updates.
        self.updateLocalPlayState(isPlaying: self.isPlayingState, position: newPosition)

        // 3. If host, update Firestore
        if isHost {
            // Debounce this update if player seeking causes rapid calls, or ensure it's only called on gesture end.
            // Set forceUpdate to true if you want this seek to immediately override any debouncing.
            await updateFirestorePlayState(forceUpdate: true)
        } else {
            // If not the host, seeking locally might cause desync.
            // The regular sync mechanism (handleServerPlayState) should correct it shortly if the host hasn't also seeked.
            // For a better non-host seek UX, the non-host could temporarily pause updates from the server
            // or send its desired seek position to the host (more complex).
            // For now, local seek will be overridden by host state if different.
            print("👤 Non-host seeked locally. Will resync to host if positions differ significantly.")
        }
    }
    
    

    // In VideoSyncService.swift

    @MainActor // Ensure player interactions happen on main thread
    private func continueSync(with player: AVPlayer) async {
        print("✅ Player is ready, continuing sync with player: \(player)...")

        // 1️⃣ Add a periodic time observer to track playback time
        setupTimeObservation(player) // This is @MainActor
        print("⏱️ Time observation setup complete for new player")

        // 2️⃣ Ensure Firebase playState listener is active
        if !isPlayStateListenerActive {
            print("🔥 Setting up new Firebase playState listener")
            setupVideoSync()
        } else {
            print("🔄 Reusing existing Firebase playState listener")
        }
        
        // --- START MODIFIED BLOCK ---
        // Update duration from the player item
        if let item = player.currentItem, let durationSeconds = item.duration.secondsIfFinite, durationSeconds > 0 {
            // A valid duration was found on the new player item. Update our service's state.
            // Only log if it's a meaningful change.
            if abs(self.currentVideoDuration - durationSeconds) > 0.1 {
                self.currentVideoDuration = durationSeconds
                print("🎞️ [VideoSyncService] Video duration updated to: \(self.currentVideoDuration)s for player: \(player)")
            }
        } else {
            // The new player's duration isn't available at this moment.
            // ✅ **CRUCIAL FIX**: DO NOT reset `currentVideoDuration` to 0 if we already have a valid one.
            if self.currentVideoDuration > 0 {
                print("⚠️ [VideoSyncService] Could not get duration from new player, but retaining existing duration of \(String(format: "%.2f", self.currentVideoDuration))s.")
            } else {
                // Only set to 0 if it was already invalid.
                self.currentVideoDuration = 0.0
                print("⚠️ [VideoSyncService] Could not get valid video duration from player item for player: \(player). Duration remains 0.")
            }
        }
        // --- END MODIFIED BLOCK ---

        // 3️⃣ Apply initial state (Snapshot > Host default)
        if let snapshot = currentSnapshot {
            print("📸 Applying snapshot - Position: \(snapshot.position), Playing: \(snapshot.isPlaying)")
            await player.seek(
                to: CMTime(seconds: snapshot.position, preferredTimescale: 1000),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            print("✅ Initial seek from snapshot complete to \(snapshot.position)s")
            try? await Task.sleep(for: .milliseconds(100)) // Allow seek to settle

            if snapshot.isPlaying {
                player.play()
                print("▶️ Resuming playback from snapshot.")
            } else {
                player.pause()
                print("⏸️ Ensuring paused state from snapshot.")
            }

            // Update local observable state to match the snapshot
            self.updateLocalPlayState(isPlaying: snapshot.isPlaying, position: snapshot.position)
            print("🔄 Local state updated from snapshot: isPlaying=\(self.isPlayingState), currentTime=\(self.currentTime)")

            clearSnapshot() // Clear the snapshot after applying it
        } else if isHost {
            print("👑 Host joining/starting: Setting initial play state. Current local time: \(self.currentTime), isPlaying: \(self.isPlayingState)")
            let initialHostPosition = self.currentTime
            let initialHostIsPlaying = true

            self.updateLocalPlayState(isPlaying: initialHostIsPlaying, position: initialHostPosition)
            print("🔄 Host: Local state updated. isPlaying=\(self.isPlayingState), currentTime=\(self.currentTime)")

            await updateFirestorePlayState(forceUpdate: true)

            if initialHostIsPlaying {
                player.play()
                print("▶️ Host: Player commanded to play.")
            } else {
                player.pause()
                print("⏸️ Host: Player commanded to pause.")
            }
        } else { // Non-host, no snapshot
            print("👤 Non-host joining (no snapshot): Pausing and waiting for Firestore state. Current local time: \(self.currentTime)")
            self.updateLocalPlayState(isPlaying: false, position: self.currentTime)
            player.pause()
            print("⏸️ Non-host: Player paused, awaiting server state.")
        }
        print("✅ Sync initialization process continued for player: \(player).")
    }

    // MARK: - Play / Pause / Seek Handling (Triggered by UI or Host)

    // This should be called from UI interaction (play/pause button) or internal logic
    // Needs to run on MainActor because it interacts with player
    @MainActor
    func handlePlayPauseToggle() async {
        guard let player = currentPlayer else {
            print("⚠️ Cannot toggle play/pause: No player.")
            return
        }
        let targetState = player.timeControlStatus != .playing
        await handlePlayPause(isPlaying: targetState)
    }
    
    // VideoSyncService.swift
    func isConfigured(for eventId: String, userId: String) -> Bool {
        return self.eventId == eventId && self.userId == userId && isWithinEventTime
    }
    
    // MARK: - Snapshot helper
    /// Store a local playback snapshot that other views can restore later.
    func storePlaybackSnapshot(position: Double, isPlaying: Bool) {
        currentSnapshot = SyncSnapshot(position: position, isPlaying: isPlaying)
    }

    // MARK: - Video‑end callback plumbing
    private var videoEndHandler: (() -> Void)?

    /// Register a closure that should run *after* `handleVideoEnd()` finishes.
    func setupVideoEndHandler(_ handler: @escaping () -> Void) {
        videoEndHandler = handler
    }


    // Central function to handle play/pause intent, updating player and Firestore (if host)
    @MainActor
    func handlePlayPause(isPlaying desiredPlayState: Bool) async {
        print("⏯️ handlePlayPause called with isPlaying: \(desiredPlayState)")
        guard let player = currentPlayer else {
            print("⚠️ Cannot handle play/pause: No player.")
            return
        }

        // --- 1. Update Player ---
        if desiredPlayState && player.timeControlStatus != .playing {
            print("▶️ Commanding player to play")
            player.play()
        } else if !desiredPlayState && player.timeControlStatus != .paused {
            print("⏸️ Commanding player to pause")
            player.pause()
        } else {
            print("ℹ️ Player already in desired state (\(desiredPlayState ? "playing" : "paused"))")
        }

        // --- 2. Update Local State ---
        // Ensure local state reflects the command immediately, using current player time.
        // It's important that self.isPlayingState and self.currentTime are correct
        // before calling updateFirestorePlayState.
        let currentPosition = player.currentTime().seconds
        if isPlayingState != desiredPlayState || abs(self.currentTime - currentPosition) > 0.1 { // Update if play state or time changed significantly
            updateLocalPlayState(isPlaying: desiredPlayState, position: currentPosition)
        }


        // --- 3. Update Firestore (if Host) ---
        if isHost {
            // User-initiated actions should update Firestore promptly, bypassing regular debounce.
            print("👑 Host action: Forcing Firestore update for play/pause.")
            await updateFirestorePlayState(forceUpdate: true) // <<<--- MODIFIED HERE
        }
    }

    // MARK: - State Updates (Local & Firestore)

    // Updates observable properties, MUST be called on MainActor
    @MainActor
    private func updateLocalPlayState(isPlaying: Bool, position: Double) {
        var changedState = false
        if self.isPlayingState != isPlaying {
            self.isPlayingState = isPlaying
            print("🔄 Updated local isPlayingState: \(self.isPlayingState)")
            changedState = true
        }

        // Using a small threshold for currentTime update to avoid excessive @Observable triggers
        // if the position changes are minuscule and frequent from non-player sources.
        // However, if this function is primarily driven by player events or significant state changes,
        // the threshold might not be strictly necessary. For snapshot restoration, it's good to set it accurately.
        if abs(self.currentTime - position) > 0.01 || changedState { // Update if significantly different or if play state changed
            self.currentTime = position
            // This log can be very noisy if updated frequently by time observer.
            // Consider conditional logging or removing if too verbose.
             print("🔄 Updated local currentTime: \(String(format: "%.2f", self.currentTime))s (from received position: \(String(format: "%.2f", position))s)")
        }
    }

    // Pushes the current local state (`isPlayingState`, `currentTime`) to Firestore
    // Should only be called by the host. Can run async.
    private func updateFirestorePlayState(forceUpdate: Bool = false) async {
        guard isHost, let syncRef = getBasePath() else {
            // This log can be noisy if called frequently by non-hosts, but useful for debugging this specific issue
            // print("🚫 updateFirestorePlayState: Not host or no sync path. isHost: \(isHost), eventId: \(self.eventId ?? "nil")")
            return
        }

        let now = Date()
        if !forceUpdate, let lastUpdate = lastSyncUpdate, now.timeIntervalSince(lastUpdate) < 1.5 {
            print("🔄 Skipping Firestore write due to debounce. Current local state: isPlaying=\(isPlayingState), pos=\(String(format: "%.2f", currentTime)). Forced: \(forceUpdate)")
            return
        }
        if forceUpdate {
            print("⚡️ Forcing Firestore playState update (bypassing debounce).")
        }
        lastSyncUpdate = now

        let updateId = UUID().uuidString
        let data: [String: Any] = [
            "isPlaying": isPlayingState,
            "playbackPosition": currentTime,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": updateId
        ]

        print("🔥 Host pushing to Firestore (\(syncRef.document("playState").path)): isPlaying=\(isPlayingState), pos=\(String(format: "%.2f", currentTime)), updateId=\(updateId)")
        do {
            try await syncRef.document("playState").setData(data, merge: true)
            print("✅ Firestore playState updated successfully with updateId: \(updateId).")
            await MainActor.run { // Update property on main thread
                self.lastFirestorePlayStateUpdateId = updateId
            }
        } catch {
            print("❌ Failed to update Firestore play state: \(error.localizedDescription)")
            await MainActor.run { // Update observable error
                self.lastError = VideoSyncError.firestoreError(error.localizedDescription)
            }
        }
    }

    // MARK: - Firestore Listeners

    private func setupVideoSync() {
        guard let syncRef = getBasePath() else {
            print("❌ Failed to get base path for video sync listener")
            return
        }
        guard !isPlayStateListenerActive else {
            print("ℹ️ PlayState listener already active.")
            return
        }

        print("👂 Setting up Firestore playState listener...")
        let playStateListener = syncRef.document("playState")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("❌ PlayState listener error: \(error.localizedDescription)")
                    Task { // Ensure error update is on main thread
                        await MainActor.run {
                            self.lastError = VideoSyncError.firestoreError(error.localizedDescription)
                        }
                    }
                    return
                }

                guard let data = snapshot?.data() else {
                    print("⚠️ PlayState snapshot data is nil. Initial state?")
                    // If it's the first time and we are host, we might want to create the initial state here
                    // but initializeRoom should handle that.
                    return
                }

                guard let serverIsPlaying = data["isPlaying"] as? Bool,
                      let serverPosition = data["playbackPosition"] as? Double else {
                    print("⚠️ Missing or invalid data in playState snapshot: \(data)")
                    return
                }
                let serverUpdateId = data["updateId"] as? String // Get the update ID

                // --- Echo Prevention ---
                // Check if this update originated from this client
                if let localUpdateId = self.lastFirestorePlayStateUpdateId, localUpdateId == serverUpdateId {
                    print("🔄 Ignoring Firestore update (echo detected)")
                    return
                }

                print("📥 Received Firestore playState: isPlaying=\(serverIsPlaying), pos=\(String(format: "%.2f", serverPosition))")

                // --- Apply State (if not Host) ---
                // Host relies on its local player time observer, non-hosts sync to Firestore
                if !self.isHost {
                    // Update local state and player on the main thread
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        // Update local state first (important for consistency)
                        self.updateLocalPlayState(isPlaying: serverIsPlaying, position: serverPosition)
                        // Then adjust the player
                        self.handleServerPlayState(isPlaying: serverIsPlaying, seconds: serverPosition)
                    }
                } else {
                    // Host received an update (potentially from another host taking over or manual edit)
                    // Optional: Could add logic for host to reconcile if state drastically differs,
                    // but generally host drives the state.
                    print("👑 Host received Firestore update, typically ignored unless checking for conflicts.")
                    // Update local state from server ONLY IF it differs significantly and is more recent?
                    // This can get complex. Simplest is Host ignores external changes unless it loses host status.
                }
            }

        // --- Finalize Listener Setup ---
        // Must ensure listener removal happens correctly in cleanup
        // Use a Task to safely append to listeners array if accessed from multiple threads (though unlikely here)
        Task { @MainActor in // Modifying listeners array, safer on main
            listeners.append(playStateListener)
            isPlayStateListenerActive = true
            print("✅ Firestore playState listener is now active.")
        }
    }

    // Should run on MainActor as it modifies player state

    @MainActor
    private func handleServerPlayState(isPlaying: Bool, seconds: Double) {
        // Note: self.isPlayingState and self.currentTime should have already been updated
        // by updateLocalPlayState in the listener callback before this function is called.
        // This function's job is to make the AVPlayer match that new local state.

        print("🖥️ Applying server state to player: targetIsPlaying=\(isPlaying), targetPos=\(String(format: "%.2f", seconds))")

        guard let player = currentPlayer else {
            print("❌ handleServerPlayState: No player available to apply server state.")
            return
        }

        // Guard 1: Player status must be ready
        guard player.status == .readyToPlay else {
            print("⚠️ handleServerPlayState: Player not ready (status: \(player.status)). Cannot apply server state.")
            return
        }

        // Guard 2: Player item status must be ready
        guard let currentItem = player.currentItem, currentItem.status == .readyToPlay else {
            // Access player.currentItem directly here as 'currentItem' from guard let is not in this scope
            print("⚠️ handleServerPlayState: Player item not ready (status: \(player.currentItem?.status ?? .unknown)). Cannot apply server state.") // CORRECTED
            if let itemError = player.currentItem?.error { // CORRECTED
                print("🔍 Player item error: \(itemError.localizedDescription)")
            }
            return
        }

        let localTime = player.currentTime().seconds
        let drift = abs(localTime - seconds)
        let needsSeek = drift > syncThreshold

        Task { @MainActor in
            if needsSeek {
                print("⏱️ handleServerPlayState: Large desync (\(String(format: "%.2f", drift))s). Seeking player from \(String(format: "%.2f", localTime))s to \(String(format: "%.2f", seconds))s...")
                await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000),
                                  toleranceBefore: .zero, toleranceAfter: .zero)
                print("✅ handleServerPlayState: Seek completed. Player now at \(player.currentTime().seconds)s.")
            }

            if self.isPlayingState {
                if player.timeControlStatus != .playing {
                    print("▶️ handleServerPlayState: Commanding player to PLAY. Current status: \(player.timeControlStatus)")
                    player.play()
                } else {
                    print("ℹ️ handleServerPlayState: Player already playing, as per server state.")
                }
            } else {
                if player.timeControlStatus != .paused {
                    print("⏸️ handleServerPlayState: Commanding player to PAUSE. Current status: \(player.timeControlStatus)")
                    player.pause()
                } else {
                    print("ℹ️ handleServerPlayState: Player already paused, as per server state.")
                }
            }
        }
    }
    // Sets up listener for active viewer count
    private func setupPresenceListener() {
        guard let syncRef = getBasePath() else { return }

        print("👂 Setting up Firestore presence listener...")
        let presenceListener = syncRef.document("presence")
            .collection("activeViewers")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("❌ Presence listener error: \(error.localizedDescription)")
                    Task { await MainActor.run { self.lastError = VideoSyncError.firestoreError(error.localizedDescription) } }
                    return
                }

                guard let documents = snapshot?.documents else {
                    print("⚠️ Presence snapshot documents are nil.")
                    return
                }

                let count = documents.count
                print("👥 Active viewers count: \(count)")

                // Update the @Observable property on the main thread
                Task { @MainActor [weak self] in
                    self?.activeViewerCount = count
                }
            }
        Task { @MainActor in // Modify listeners array on main thread
             listeners.append(presenceListener)
             print("✅ Firestore presence listener is now active.")
        }
    }

    // Sets up listener for host changes
    private func setupHostListener() {
        guard let syncRef = getBasePath() else { return }

        print("👂 Setting up Firestore host listener...")
        let hostListener = syncRef.document("host")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("❌ Host listener error: \(error.localizedDescription)")
                    Task { await MainActor.run { self.lastError = VideoSyncError.firestoreError(error.localizedDescription) } }
                    // If host doc fails, maybe trigger election? Risky.
                    return
                }

                guard let data = snapshot?.data(),
                      let hostId = data["hostId"] as? String,
                      !hostId.isEmpty, // Ensure hostId is not empty
                      let status = data["status"] as? String,
                      status == "active" else { // Ensure host status is active

                    print("⚠️ Host document data missing, empty, or inactive. Initiating election.")
                    // No valid host found, initiate election (run async)
                    Task { [weak self] in
                        await self?.initiateHostElection()
                    }
                    return
                }

                // --- Host Status Update ---
                let newIsHost = (hostId == self.userId)
                print("👑 Received host update. Current Host ID: \(hostId). Am I host? \(newIsHost)")

                // Update the @Observable property on the main thread ONLY if it changes
                if self.isHost != newIsHost {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        let wasHost = self.isHost
                        self.isHost = newIsHost
                        print("👑 Host status changed: \(self.isHost)")

                        // If just became host, maybe force push state?
                        if self.isHost && !wasHost {
                             print("👑 Just became host! Ensuring Firestore state is up-to-date.")
                             await self.updateFirestorePlayState(forceUpdate: true) // Force immediate update
                         }
                        // If just lost host status, stop sending updates (handled by isHost check in update func)
                        if !self.isHost && wasHost {
                            print("👑 Lost host status.")
                            // Non-hosts rely on Firestore, local timer stops pushing.
                        }
                    }
                }
            }
        Task { @MainActor in // Modify listeners array on main thread
            listeners.append(hostListener)
            print("✅ Firestore host listener is now active.")
        }
    }


    // MARK: - Time Observation (Player)

    // Should be called on MainActor as it interacts with AVPlayer observers
    @MainActor
    private func setupTimeObservation(_ player: AVPlayer) {
        print("⏱️ Setting up time observation for player")

        // 1️⃣ Remove existing time observer before adding a new one
        removeTimeObserverIfNeeded(from: player) // Pass player explicitly

        // 2️⃣ Define update interval
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)) // More frequent local updates

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            // 3️⃣ Update local currentTime immediately (already on main queue)
            let newTime = time.seconds
            // Avoid updating if time is invalid
            guard newTime.isFinite, !newTime.isNaN else { return }

            // Update local state (no need for threshold here, observer controls frequency)
             self.currentTime = newTime
             // print("⏱️ Local Time Observer: \(String(format: "%.2f", newTime))") // Very noisy

            // 4️⃣ If Host, push updates to Firestore (debounced)
            // Run the Firestore update logic asynchronously
            if self.isHost {
                // Don't await here, let it run in background
                Task { [weak self] in // Use Task for async work
                    await self?.updateFirestorePlayState()
                }
            }
        }
        print("✅ Time observation setup complete")
    }

    // Should be called on MainActor
    @MainActor
    private func removeTimeObserverIfNeeded(from player: AVPlayer?) {
        guard let token = timeObserverToken, let playerToRemoveFrom = player else {
            // print("ℹ️ No time observer to remove or player is nil")
            return
        }
        print("🧹 Removing time observer from player instance.")
        playerToRemoveFrom.removeTimeObserver(token)
        timeObserverToken = nil
        print("✅ Time observer removed.")
    }


    // MARK: - Monitoring (Presence, Event Time)

    // Starts timers for periodic tasks
    private func startMonitoring() {
        // Ensure timers are stopped before starting new ones
        cleanupTimers()
        print("⏳ Starting monitoring timers (Presence, Event Time)")

        // Event time monitoring (Repeats every 60s)
        let eventTimer = Timer(timeInterval: 60.0, repeats: true) { [weak self] _ in
             self?.checkEventTime() // Updates observable property, needs main thread
         }
        // Schedule on main run loop
        RunLoop.main.add(eventTimer, forMode: .common)

        // Presence update timer (Repeats every `presenceInterval`)
        let presenceTimer = Timer(timeInterval: presenceInterval, repeats: true) { [weak self] _ in
             // Perform presence update async
             Task { [weak self] in
                 await self?.updatePresence()
             }
         }
        // Schedule on main run loop
        RunLoop.main.add(presenceTimer, forMode: .common)


        Task { @MainActor in // Modify timers array on main thread
             timers.append(contentsOf: [eventTimer, presenceTimer])
             print("✅ Monitoring timers started.")
        }
    }

    // Checks if the event is still active, updates state, potentially cleans up
    @MainActor private func checkEventTime() {
        let wasWithinTime = self.isWithinEventTime
        updateEventTimeStatus() // Updates self.isWithinEventTime

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if wasWithinTime && !self.isWithinEventTime { // If it *was* in time, and *now* it's not
                print("⏱️ Event time ended. Cleaning up...")
                Task { [weak self] in // This Task is for the cleanup itself
                    await self?.cleanup(level: .full)
                }
                self.dismissImmersiveSpace?()
            }
        }
    }
    
    // Updates the observable isWithinEventTime property
    @MainActor
    private func updateEventTimeStatus() {
        guard let event = event else {
            isWithinEventTime = false
            return
        }
        let now = Date()
        let inTime = (event.date ... event.end).contains(now)

        if isWithinEventTime != inTime { // Only if the state actually changes
            isWithinEventTime = inTime
            if !inTime { currentPlayer?.pause() } // Pause player if event ended
        }
    }


    // MARK: - Presence Management (Firestore)

    // Registers user presence in Firestore. Async.
    private func registerPresence() async {
        print("👤 Registering presence...")
        guard let syncRef = getBasePath(), let userId = userId else {
            print("❌ Failed to register presence: Missing path or userId")
            return
        }
        let presenceRef = syncRef.document("presence").collection("activeViewers").document(userId)

        do {
            // Use merge=true to update timestamp if already exists, or create if not
            try await presenceRef.setData([
                "userId": userId,
                "lastSeen": FieldValue.serverTimestamp(),
                "joined": FieldValue.serverTimestamp(), // Set join time only once ideally
                "status": "active",
                "isHost": isHost // Include host status
            ], merge: true) // Use merge to handle existing docs gracefully

            print("✅ Presence registered/updated for \(userId)")

            // Optional: Set up onDisconnect handler (requires Realtime Database or careful handling)
            // Firestore doesn't have a direct onDisconnect like RTDB.
            // Relies on periodic updates and cleanup of stale entries.

        } catch {
            print("❌ Error registering/updating presence: \(error.localizedDescription)")
            Task { await MainActor.run { self.lastError = VideoSyncError.firestoreError(error.localizedDescription) } }
            // Consider retry logic if needed
        }
    }

    // Periodically updates the user's lastSeen time and host status. Async.
    private func updatePresence() async {
        // print("👤 Updating presence heartbeat...") // Can be noisy
        guard let syncRef = getBasePath(), let userId = userId else { return }
        let presenceRef = syncRef.document("presence").collection("activeViewers").document(userId)
        let hostRef = syncRef.document("host")

        do {
            // Update main presence doc
            try await presenceRef.setData([
                "lastSeen": FieldValue.serverTimestamp(),
                "isHost": isHost // Keep host status updated here too
                // "currentTime": self.currentTime // Optionally update current time watched?
            ], merge: true) // Use merge to avoid overwriting 'joined'

            // If host, update the main host document's lastActive timestamp
            if isHost {
                try await hostRef.setData([
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "hostId": userId, // Ensure hostId is correct
                    "status": "active" // Ensure status is active
                    ], merge: true)
            }
            // print("✅ Presence heartbeat updated.") // Can be noisy
        } catch {
            print("❌ Error updating presence/host heartbeat: \(error.localizedDescription)")
            // If update fails, maybe try to re-register?
            // Check if doc exists, if not call registerPresence?
            Task { await MainActor.run { self.lastError = VideoSyncError.firestoreError(error.localizedDescription) } }
        }
    }

    // Removes user presence from Firestore. Async. Critical for host election.
    private func cleanupDatabasePresence(eventId: String, userId: String) async {
        print("🧹 Cleaning up database presence for User: \(userId), Event: \(eventId)")
        guard let syncRef = getBasePath() else {
            print("❌ Cannot cleanup presence: Failed to get Firestore path.")
            return
        }
        let presenceRef = syncRef.document("presence").collection("activeViewers").document(userId)
        let hostRef = syncRef.document("host")

        do {
            // --- Check if current user is host BEFORE deleting presence ---
            var amIHost = false
            var shouldElectNewHost = false
            do {
                let hostDoc = try await hostRef.getDocument()
                if let currentHostId = hostDoc.data()?["hostId"] as? String, currentHostId == userId {
                    print("ℹ️ User leaving is the current host.")
                    amIHost = true
                    shouldElectNewHost = true // Mark that election is needed
                    // Optionally clear the host document field immediately or let election handle it
                    // try await hostRef.updateData(["hostId": "", "status": "inactive"])
                }
            } catch {
                 print("⚠️ Could not read host document during cleanup: \(error.localizedDescription)")
                 // Proceed with caution, might not elect properly if host doc is unreadable
            }

            // --- Delete presence document ---
            print("🗑️ Attempting to delete presence document...")
            try await presenceRef.delete()
            print("✅ Presence document deleted for \(userId).")

            // --- Trigger Host Election if needed ---
            // Perform election *after* successfully deleting presence,
            // ensuring the leaving host isn't considered.
            if shouldElectNewHost {
                print("🗳️ Triggering host election after host left.")
                await initiateHostElection(skipSelf: true) // Tell election logic to exclude this user implicitly
            }

            // --- Update historical data (Optional) ---
             // Consider adding this if needed, similar to original code

        } catch {
            print("❌ Error cleaning up database presence: \(error.localizedDescription)")
             Task { await MainActor.run { self.lastError = VideoSyncError.firestoreError(error.localizedDescription) } }
             // Retry logic might be needed here for critical cleanup
        }
    }


    // MARK: - Host Election

    // Initiates host election process. Async.
    // MARK: - Host Election
    // Initiates a host‑election transaction.
    private func initiateHostElection(skipSelf: Bool = false) async {
        print("🗳️ Initiating host election…")
        guard let syncRef = getBasePath(), let currentUserId = self.userId else {
            print("❌ Host election failed: Missing path or userId.")
            return
        }

        // 1)  Pick the oldest active viewer *outside* the transaction.
        var potentialHostId: String?
        do {
            let viewers = try await syncRef
                .document("presence")
                .collection("activeViewers")
                .order(by: "joined", descending: false)
                .limit(to: 5)
                .getDocuments()

            for doc in viewers.documents {
                let cid = doc.documentID
                if skipSelf && cid == currentUserId { continue }
                potentialHostId = cid
                break
            }
            print("👥 Candidate host: \(potentialHostId ?? "<none>")")
        } catch {
            // UNCOMMENT AND USE THIS:
            print("❌ Error during host-election transaction for event '\(self.eventId ?? "N/A")': \(error.localizedDescription)")
            await MainActor.run {
                self.lastError = VideoSyncError.firestoreError(error.localizedDescription)
            }
        }

        // 2)  **Sync** version of `runTransaction` (the async variant isn’t in your SDK yet).
        do {
            try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                let hostRef = syncRef.document("host")

                // Read the current host doc *synchronously* inside the transaction.
                let hostSnap: DocumentSnapshot
                do {
                    hostSnap = try transaction.getDocument(hostRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                if
                    let data = hostSnap.data(),
                    let existing = data["hostId"] as? String,
                    let status  = data["status"]  as? String,
                    status == "active",
                    existing != (skipSelf ? currentUserId : "")
                {
                    // Someone else is already the active host – abort.
                    print("ℹ️ Active host (\(existing)) already exists. Aborting election.")
                    return nil
                }

                // Either assign the new host or mark the room inactive.
                if let newHost = potentialHostId {
                    print("👑 Assigning new host: \(newHost)")
                    transaction.setData([
                        "hostId":     newHost,
                        "timestamp":  FieldValue.serverTimestamp(),
                        "lastUpdate": FieldValue.serverTimestamp(),
                        "status":     "active"
                    ], forDocument: hostRef, merge: true)
                } else {
                    print("⚠️ No eligible host — marking inactive.")
                    transaction.setData([
                        "hostId":    "",
                        "timestamp": FieldValue.serverTimestamp(),
                        "status":    "inactive"
                    ], forDocument: hostRef, merge: true)
                }
                return nil // Required return value
            })

            print("✅ Host election transaction completed successfully.")
        } catch {
            print("❌ Error during host‑election transaction: \(error.localizedDescription)")
            await MainActor.run {
                self.lastError = VideoSyncError.firestoreError(error.localizedDescription)
            }
        }
    }



    // Attempts to claim host status if none exists. Async.
    private func becomeHost() async -> Bool {
        print("👑 Attempting to become host...")
        guard let syncRef = getBasePath(), let userId = userId else {
            print("❌ Cannot become host: Missing path or userId.")
            return false
        }
        let hostRef = syncRef.document("host")

        do {
            // --- Use Transaction to claim host spot ---
            try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                let hostDoc: DocumentSnapshot
                do {
                    hostDoc = try transaction.getDocument(hostRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    print("❌ Transaction failed: Could not read host document.")
                    return nil // Propagate error
                }

                // Check if a host already exists and is active
                if let hostData = hostDoc.data(),
                   let existingHostId = hostData["hostId"] as? String, !existingHostId.isEmpty,
                   let status = hostData["status"] as? String, status == "active" {
                    print("ℹ️ Transaction: Host \(existingHostId) already exists. Cannot claim.")
                    // We didn't become host, but transaction succeeded in reading
                    return "HOST_EXISTS" // Special value to indicate existing host
                }

                // No active host, claim it
                print("👑 Transaction: Claiming host status for \(userId).")
                transaction.setData([
                    "hostId": userId,
                    "timestamp": FieldValue.serverTimestamp(),
                    "lastUpdate": FieldValue.serverTimestamp(),
                    "status": "active"
                ], forDocument: hostRef) // Overwrite/Set data

                return "HOST_CLAIMED" // Special value indicating success
            })

            // --- Check Transaction Result ---
            // If the transaction completed without error, check if we claimed it.
            // We need to re-read the host doc *after* the transaction to be sure,
            // as the listener update might be slightly delayed.
            let finalHostDoc = try await hostRef.getDocument()
            if let finalHostId = finalHostDoc.data()?["hostId"] as? String, finalHostId == userId {
                 print("✅ Successfully became host (verified after transaction).")
                 // Update local state on main thread
                 await MainActor.run { self.isHost = true }
                 // Force an update to Firestore state now that we are host
                 await self.updateFirestorePlayState(forceUpdate: true)
                 return true
            } else {
                 print("ℹ️ Did not become host (likely claimed by another user concurrently).")
                 await MainActor.run { self.isHost = false }
                 return false
            }

        } catch {
            // UNCOMMENT AND USE THIS:
            print("❌ Error during becomeHost transaction for event '\(self.eventId ?? "N/A")', userId '\(self.userId ?? "N/A")': \(error.localizedDescription)")
            Task { await MainActor.run { self.lastError = VideoSyncError.firestoreError(error.localizedDescription); self.isHost = false } }
            return false
        }
    }

    // Initializes room state if needed (e.g., creates initial documents). Async.
    private func initializeRoom() async -> Bool {
        print("🏠 Initializing video sync room (transactional initial setup)...")
        guard let syncRef = getBasePath(), let currentUserId = self.userId else {
            print("❌ VideoSyncService.initializeRoom: Failed to get Firestore path or missing userId.")
            await MainActor.run { self.lastError = VideoSyncError.syncConfigurationFailed }
            return false
        }

        let hostRef = syncRef.document("host")
        let playStateRef = syncRef.document("playState")
        // let presenceBaseDocRef = syncRef.document("presence") // If you have a base 'presence' document

        do {
            let hostDocSnapshot = try await hostRef.getDocument()

            if !hostDocSnapshot.exists {
                print("🆕 VideoSyncService.initializeRoom: Host document for event \(self.eventId ?? "unknown") doesn't exist. Attempting transactional creation of initial room state...")
                
                // This variable will be checked after the transaction to see if it succeeded.
                var transactionError: Error?

                try await db.runTransaction { (transaction, errorPointer) -> Any? in
                    // --- Start of the non-throwing closure ---
                    do {
                        // Re-check inside transaction for true atomicity
                        let currentHostSnapInTransaction = try transaction.getDocument(hostRef) // This can throw
                        
                        if !currentHostSnapInTransaction.exists {
                            print("🧱 Transaction: Creating initial documents for \(self.eventId ?? "unknown").")
                            // 1. Host Document (inactive, to be claimed)
                            transaction.setData([
                                "hostId": "",
                                "status": "inactive",
                                "timestamp": FieldValue.serverTimestamp(),
                                "lastUpdate": FieldValue.serverTimestamp()
                            ], forDocument: hostRef)

                            // 2. PlayState Document
                            transaction.setData([
                                "isPlaying": false,
                                "playbackPosition": 0.0,
                                "updatedAt": FieldValue.serverTimestamp(),
                                "updateId": UUID().uuidString
                            ], forDocument: playStateRef)
                            
                            // 3. Optional: Base Presence Document
                            // let presenceDocRefForCreation = syncRef.document("presence")
                            // transaction.setData(["created": FieldValue.serverTimestamp()], forDocument: presenceDocRefForCreation)

                            print("🧱 Transaction: Initial room documents staged for creation.")
                        } else {
                            print("🧱 Transaction: Host document found to exist during transaction for event \(self.eventId ?? "unknown"). Skipping initial creation by this transaction.")
                        }
                        // If everything in the 'do' block succeeds, we return nil (or any other success indicator if your pattern needs one)
                        // and errorPointer remains nil.
                        return nil
                    } catch let catchedError {
                        // UNCOMMENT AND USE THIS:
                        print("❌ Transaction Error during initializeRoom for event '\(self.eventId ?? "N/A")': \(catchedError.localizedDescription)")
                        errorPointer?.pointee = catchedError as NSError
                        return nil
                    }
                    // --- End of the non-throwing closure ---
                }
                // Note: The `try await db.runTransaction` itself can throw if the transaction ultimately fails after retries
                // (e.g., due to repeated errors set via errorPointer or other reasons).
                // This outer `do-catch` will catch such an overall transaction failure.

                print("✅ VideoSyncService.initializeRoom: Transactional room initialization attempt completed for event \(self.eventId ?? "unknown").")
            } else {
                print("✅ VideoSyncService.initializeRoom: Room documents (host doc) already exist for event \(self.eventId ?? "unknown").")
            }

            _ = await becomeHost()
            await registerPresence()
            return true

        } catch {
            // UNCOMMENT AND USE THIS:
            print("❌ VideoSyncService.initializeRoom: Error during room initialization for event \(self.eventId ?? "unknown"): \(error.localizedDescription)")
            let specificError = VideoSyncError.firestoreError("Room init failed: \(error.localizedDescription)") // This was already there
            await MainActor.run { self.lastError = specificError } // This was already there
            return false
        }
    }


    // MARK: - View State Management
    @MainActor
    func switchToView(_ state: ViewState) async {
        // Log the call and the target state immediately.
        print("🔄 switchToView called for state: \(state). Current active state: \(self.currentViewState)")

        // Prevent redundant operations if already in the target state.
        guard self.currentViewState != state else {
            print("⚠️ Already in view state: \(state). No action needed.")
            return
        }

        // Handle the current player if one exists.
        if let player = self.currentPlayer {
            print("ℹ️ switchToView: Processing existing player: \(player) for transition from \(self.currentViewState) to \(state)")

            let currentPosition = player.currentTime().seconds
            
            // --- FIX ---
            // The original code used `player.timeControlStatus == .playing`, which can be unreliable
            // during state transitions. Using the service's own tracked `isPlayingState` property
            // provides a more accurate reflection of the video's status.
            let isCurrentlyPlaying = self.isPlayingState
            
            // Create the snapshot with the corrected playback state.
            print("📸 switchToView: Storing snapshot from \(self.currentViewState) - Position: \(String(format: "%.2f", currentPosition)), isCurrentlyPlaying: \(isCurrentlyPlaying)")
            self.currentSnapshot = SyncSnapshot(position: currentPosition, isPlaying: isCurrentlyPlaying)

            // Pause the player and update sync state (if host).
            print("⏯️ switchToView: Commanding pause for player \(player) in \(self.currentViewState) via handlePlayPause.")
            await self.handlePlayPause(isPlaying: false) // This is an async call

            // Remove the time observer from this player instance.
            print("🧹 switchToView: Removing time observer from player: \(player) associated with \(self.currentViewState)")
            self.removeTimeObserverIfNeeded(from: player)

            print("ℹ️ switchToView: Player instance `self.currentPlayer` is NOT nilled out by switchToView itself.")

        } else {
            print("ℹ️ switchToView: No current player to snapshot or pause while transitioning from \(self.currentViewState).")
        }

        // Update the service's current view state.
        let previousViewState = self.currentViewState
        self.currentViewState = state
        print("➡️ switchToView: Updated currentViewState from \(previousViewState) to \(self.currentViewState)")

        // Perform environment actions like dismissing/opening windows.
        // Note: These are callbacks that get configured by the view layer.
        switch state {
        case .movieWindow:
            print("🚪 switchToView: Configuring UI for .movieWindow (e.g., dismissing immersive space)")
            self.dismissImmersiveSpace?()
        case .immersive:
            print("🚪 switchToView: Configuring UI for .immersive (e.g., dismissing movie window)")
            self.dismissWindow?("movieWindow")
        case .none:
            print("🚪 switchToView: Transitioning to .none state. This might be part of a broader cleanup or exit.")
        }
        
        print("✅ switchToView async function for state \(state) has fully completed.")
    }
    // MARK: - Video End Handling

    // Central handler for when video finishes playing naturally
    // Should be called from player's end-of-item notification
    // Needs to run on MainActor if interacting with UI/player
    @MainActor
    func handleVideoEnd() async {
        print("🏁 Handling video end sequence...")

        guard let syncRef = getBasePath() else {
            print("❌ No valid Firestore path found for video end.")
            return
        }

        // --- Update Firestore State ---
        // Mark session as ended, reset position, set paused
        let updateId = UUID().uuidString
        let endData: [String: Any] = [
            "isPlaying": false,
            "playbackPosition": 0.0, // Reset position
            "sessionEnded": true, // Custom flag indicating natural end
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": updateId
        ]
        // Push update if host
        if isHost {
            print("🔥 Host pushing video end state to Firestore.")
            do {
                try await syncRef.document("playState").setData(endData, merge: true)
                self.lastFirestorePlayStateUpdateId = updateId // Track our update
            } catch {
                 print("❌ Error marking session ended in Firestore: \(error.localizedDescription)")
                 self.lastError = VideoSyncError.firestoreError(error.localizedDescription)
             }
         }

        // --- Update Local State ---
        self.updateLocalPlayState(isPlaying: false, position: 0.0)
        // Explicitly pause player if it hasn't already stopped
        currentPlayer?.pause()

        // --- Cleanup ---
        // Perform full cleanup, as the video session is over
        print("🧹 Initiating full cleanup after video end.")
        // Run cleanup async, don't block UI thread
        Task { [weak self] in
             await self?.cleanup(level: .full)
        }

        // --- Trigger UI Dismissal ---
        // Use callbacks provided during configuration
        print("🚪 Dismissing related UI windows...")
        dismissWindow?("movieWindow")
        dismissWindow?("chatWindow") // etc.
        dismissImmersiveSpace?()

        
        videoEndHandler?()          // <‑‑ add this line
        print("✅ Video end handling complete.")
    }


    // MARK: - Cleanup & Termination

    // Central cleanup function
    // If called from UI, ensure it's on MainActor
    // If called from background (e.g., timer), be careful about UI interaction
    func cleanup(level: CleanupLevel = .full) async {
         print("=== VideoSyncService Cleanup Start (Level: \(level)) ===")

         // --- Player Related Cleanup (Needs MainActor) ---
         await MainActor.run { [weak self] in
             guard let self = self else { return }
             print("🧹 Cleaning up player resources...")
             // Remove observer from the current player instance
             removeTimeObserverIfNeeded(from: self.currentPlayer)

             // Stop player unless cleanup level allows keeping it (e.g., light for view switch)
             if level == .full || level == .partial {
                 self.currentPlayer?.pause()
                 if level == .full { // Only nil player on full cleanup
                      self.currentPlayer = nil
                      self.currentVideoDuration = 0.0
                      print("🗑️ Player instance released.")
                 }
             }
         }

         // --- Stop Timers (Safe from any thread) ---
         cleanupTimers()

         // --- Stop Listeners (Safe from any thread - listener removal is thread-safe) ---
         if level == .full {
             cleanupListeners()
         } else {
              print("ℹ️ Keeping listeners active for level: \(level)")
         }


         // --- Database Cleanup (Async, background safe) ---
         if level == .full {
             print("🧹 Performing full database cleanup...")
             if let eid = eventId, let uid = userId {
                  await cleanupDatabasePresence(eventId: eid, userId: uid) // Handles host election if needed
             } else {
                 print("⚠️ Cannot perform DB cleanup: Missing eventId or userId.")
             }
             // No need for ensureHostCleanup separately, cleanupDatabasePresence handles it.
         }

         // --- Reset State (Observable properties need MainActor) ---
         await MainActor.run { [weak self] in
             guard let self = self else { return }
             print("🔄 Resetting internal state...")
             if level == .full {
                 self.isHost = false
                 self.isPlayingState = false
                 self.currentTime = 0.0
                 self.activeViewerCount = 0 // Reset count display
                 self.eventId = nil
                 self.userId = nil
                 self.event = nil
                 self.lastError = nil
                 self.isWithinEventTime = false // Reset event time status
                 self.currentSnapshot = nil // Clear snapshot on full cleanup
                 self.currentViewState = .none
             } else if level == .partial {
                 // Keep sync state (isHost, isPlaying, time, listeners) but clear player
                 self.currentPlayer = nil // Already done above potentially
             }
             // Light cleanup only removes observer/player instance, keeps state
             print("✅ State reset complete for level: \(level)")
         }

         // --- Final log ---
         print("=== Cleanup Summary (Level: \(level)) ===")
         print("🔌 Player Instance Nil: \(currentPlayer == nil)")
         print("🔥 PlayState Listener Active: \(isPlayStateListenerActive)") // Reflects state *after* cleanupListeners potentially ran
         print("👑 Host Status: \(isHost)")
         print("✅ Cleanup Sequence Finished ===")
     }

    func cleanupListeners() {
         print("🧹 Cleaning up \(listeners.count) Firestore listeners...")
         listeners.forEach { $0?.remove() }
         listeners.removeAll()
         isPlayStateListenerActive = false // Mark listener as inactive
         print("✅ Listeners removed.")
     }

    func cleanupTimers() {
        print("🧹 Cleaning up \(timers.count) timers...")
        timers.forEach { $0?.invalidate() }
        timers.removeAll()
        print("✅ Timers invalidated.")
    }

    @objc private func handleAppTerminationNotification() {
        // This is called VERY LATE in the termination process.
        // Network requests (Firestore writes) are NOT guaranteed to complete.
        // Use synchronous methods if absolutely necessary, but prefer background execution modes.
        print("⚠️ App is terminating! Attempting quick cleanup...")

        // 1. Try to remove presence synchronously if possible? Risky.
        // Firestore doesn't offer sync methods easily. Best effort async.
        if let eid = eventId, let uid = userId {
             Task { // Fire and forget async task
                 print("⏳ Termination: Attempting async presence removal...")
                 await cleanupDatabasePresence(eventId: eid, userId: uid)
                 print("⏳ Termination: Async presence removal task finished (may not have completed network IO).")
             }
        }

        // 2. Invalidate timers/listeners (local cleanup)
        cleanupTimers()
        cleanupListeners()
        // Don't interact with player here, likely too late

        print("⚠️ Termination handler finished.")
    }


    // MARK: - Helper Methods

    func getBasePath() -> CollectionReference? {
        guard let currentEventId = self.eventId else {
            Task { await MainActor.run { self.lastError = VideoSyncError.missingEventId } }
            print("❌ getBasePath() failed: Missing event ID")
            return nil
        }
        
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yyyy"
            formatter.timeZone = TimeZone(identifier: "EST")
            return formatter
        }()
        // Use a fixed date for testing if necessary, or ensure the date used here matches test expectations
        // For tests, it might be better if self.event.date is used if available and relevant for the path
        let dateToUse = self.event?.date ?? Date() // Or just Date() if path is always based on current day
        let dateString = dateFormatter.string(from: dateToUse)

        let path = "Public Rooms/\(dateString)/Events/\(currentEventId)/sync"
        // print("📂 Firestore base path: \(path)") // Can be noisy
        return db.collection(path) // self.db is now correctly set
    }

    // Simple wrapper for timeout logic
    // Helper for running an async operation with a timeout.
    // Throws TimeoutError if the operation takes too long,
    // or rethrows any error thrown by the operation itself.
    // Put this near the top of the file (or inside the class, but NOT inside a function).
    private struct UnexpectedTimeoutCompletion: Error {}


    // Simple wrapper for timeout logic
    // MARK: - Run any async operation with a hard timeout
    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {

        try await withThrowingTaskGroup(of: T.self) { group in

            // 1️⃣  The work you actually want to run.
            group.addTask {
                try await operation()
            }

            // 2️⃣  A separate task that *only* waits and then throws.
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                print("⏰ [withTimeout] Timeout of \(seconds)s reached.")
                throw TimeoutError(duration: seconds)
            }

            // 3️⃣  Whichever child finishes first decides the result.
            //     `group.next()` returns immediately after *one* child completes.
            do {
                guard let result = try await group.next() else {
                    // Should never happen, but keeps the compiler happy.
                    print("💥 [withTimeout] group.next() returned nil.")
                    throw UnexpectedTimeoutCompletion()
                }
                // Success path — primary operation finished first.
                group.cancelAll()        // cancel the timer task
                return result

            } catch {
                // Error path — either the operation threw or the timer fired.
                group.cancelAll()        // cancel whichever task is still running
                throw error              // re-propagate
            }
        }
    }



    // Gets watch stats (ensure properties read are main-thread safe)
    func getWatchStats() async -> WatchStats {
        // Read properties on main thread
        let count = await MainActor.run { self.activeViewerCount }
        let time = Date().timeIntervalSince(joinTime) // joinTime is constant
        return WatchStats(
            watchTime: time,
            viewerCount: count
        )
    }

    // Needs MainActor if updating self.lastError
    @MainActor
    private func handleError(_ error: Error) {
         print("❌ Error encountered: \(error.localizedDescription)")
         // Log detailed error info if possible
         if let firestoreError = error as? NSError, firestoreError.domain == FirestoreErrorDomain {
             print("   Firestore Error Code: \(firestoreError.code)")
         }
         // Update observable lastError property
         self.lastError = error
         // Potentially trigger UI feedback or recovery mechanisms
     }

    // Deinit
     deinit {
         print("🗑️ VideoSyncService deinitializing.")
         // Remove notification center observers
         NotificationCenter.default.removeObserver(self)
         // Ensure timers and listeners are cleaned up if not already
         cleanupTimers()
         cleanupListeners()
     }
}

// Helper extension for TimeInterval formatting (Optional)
extension TimeInterval {
    func formatted() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: self) ?? "00:00"
    }
}
