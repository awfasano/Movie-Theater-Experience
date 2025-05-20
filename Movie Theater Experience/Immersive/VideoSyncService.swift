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


enum VideoSyncError: Error {
    case missingDatabase
    case missingEventId
    case invalidPath(String)
    case firestoreError(String)
    case playerNotReady
    case syncConfigurationFailed
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
    // Make the snapshot type public
    public struct SyncSnapshot {
        let position: Double
        let isPlaying: Bool
    }

    // Add public property to access snapshot
    // Ensure write access is controlled and potentially main-thread
    private(set) var currentSnapshot: SyncSnapshot?

    // Make the view state accessible
    // Ensure write access is controlled and potentially main-thread
    private(set) var currentViewState: ViewState = .none


    // MARK: - Public / Observable
    // These will be updated from various contexts (Firebase callbacks, timers, direct calls)
    // Ensure updates happen on the main thread.
    var isHost = false
    var isWithinEventTime = false
    var lastError: Error?
    var isPlaying: Bool { isPlayingState } // Public getter is fine
    var currentTime: Double = 0.0
    var activeViewerCount: Int = 0 // Needs main thread update

    // Callbacks should likely be dispatched to main thread if they trigger UI changes
    var dismissWindow: ((String) -> Void)?
    var dismissImmersiveSpace: (() -> Void)?


    // MARK: - Private
    private var isPlayingState = false // Internal state, update on main thread if driving `isPlaying`
    private let db: Firestore
    private var lastPresenceUpdate: Date?
    private let spaceManager = ImmersiveSpaceManager.shared // Assuming ImmersiveSpaceManager is @MainActor

    /// The *actual* player we are syncing with.
    /// Keep it here so we can remove the time observer from
    /// this exact instance in `cleanup()`.
    private var currentPlayer: AVPlayer? // Player interactions should be on main thread
    private var timeObserverToken: Any?
    // syncSnapshot is internal, doesn't need main thread unless accessed across threads unsafely
    // private var syncSnapshot: (position: Double, isPlaying: Bool)? // Replaced by currentSnapshot
    private var isPlayStateListenerActive = false
    private var lastSyncUpdate: Date?
    private var lastFirestorePlayStateUpdateId: String? // To prevent echo updates

    // Other properties...
    private let joinTime = Date()

    // Room info
    private var event: CalendarEvent?
    private var eventId: String?
    private var userId: String?

    // Firebase listeners
    private var listeners: [ListenerRegistration?] = []
    private var timers: [Timer?] = []

    // Constants
    private let syncThreshold = 3.0 // seconds
    private let presenceInterval = 10.0 // seconds
    private let playerReadyTimeout = 5.0 // seconds

    // Singleton
    static let shared = VideoSyncService()

    // MARK: - Init
    private init() {
        // Firestore setup is fine off-main thread
        let settings = FirestoreSettings()
        // Persistence is useful for offline, but disable if causing issues with real-time sync
        // settings.isPersistenceEnabled = false // Keep as false per original code
        settings.isSSLEnabled = true

        self.db = Firestore.firestore(database: "movieexperiencedb") // Replace with your actual DB ID if needed
        self.db.settings = settings
        print("🔥 Firestore Initialized")

        // Listen for app termination to clean up presence
        // Note: This notification might not always fire reliably (e.g., crashes)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppTerminationNotification), name: UIApplication.willTerminateNotification, object: nil)
    }

    // MARK: - Public Methods
    func configureSync(eventId: String, userId: String, event: CalendarEvent) async -> Bool {
        print("⚙️ Configuring Sync for Event: \(eventId), User: \(userId)")
        // Reset state for configuration
        await MainActor.run { // Update observable properties on main thread
            self.eventId = eventId
            self.userId = userId
            self.event = event
            // Reset other relevant state upon reconfiguration if necessary
            self.isHost = false
            self.isPlayingState = false
            self.currentTime = 0.0
            self.activeViewerCount = 0
            self.currentSnapshot = nil // Clear snapshot on new sync config
            self.isPlayStateListenerActive = false // Ensure listeners are setup anew
        }

        // Update event time (can be done async)
        // 1️⃣ Update the flag on the MainActor
        await MainActor.run { self.updateEventTimeStatus() }

        // 2️⃣ Read the flag (also on the MainActor) and store it
        let inTime = await MainActor.run { self.isWithinEventTime }

        // 3️⃣ Guard on the Boolean you just fetched
        guard inTime else {
            print("❌ Outside event time window, cannot sync")
            await MainActor.run {
                self.lastError = VideoSyncError.syncConfigurationFailed
            }
            return false
        }

        // Initialize room state and presence (async Firestore operations)
        let roomInitialized = await initializeRoom()
        guard roomInitialized else {
             print("❌ Failed to initialize room state.")
             await MainActor.run {
                 self.lastError = VideoSyncError.syncConfigurationFailed
             }
             return false
         }

        // Start monitoring timers (presence, event time)
        startMonitoring() // Sets up timers, ensure callbacks update main thread if needed

        // Setup Firestore listeners *after* basic room init
        // No need to wait for listeners here, they run in background
        setupPresenceListener()
        setupHostListener() // Setup host listener early
        // setupVideoSync() will be called by startSync when player is ready

        print("✅ Sync Service Configured Successfully")
        return true
    }

    // Should be called on MainActor as it deals with AVPlayer
    @MainActor
    func startSync(with newPlayer: AVPlayer) async {
        print("⏯️ VideoSyncService starting sync with new player...")

        // --- Pre-checks ---
        guard isWithinEventTime else {
            print("❌ Cannot sync - outside event time")
            // Update observable error on main thread
            self.lastError = VideoSyncError.syncConfigurationFailed
            return
        }

        // --- Cleanup existing player state if different ---
        if let current = currentPlayer, current !== newPlayer {
            print("🧹 Player instance changed. Cleaning up observer for previous player.")
            removeTimeObserverIfNeeded(from: current) // Pass player explicitly
            // Optionally pause the old player if it wasn't already handled elsewhere
            // current.pause()
        } else if let current = currentPlayer, current === newPlayer {
            print("⚠️ Sync called with the same player instance. Re-initializing sync process.")
            // Still remove observer to ensure it's set up correctly in continueSync
            removeTimeObserverIfNeeded(from: current)
        }

        // --- Setup new player ---
        self.currentPlayer = newPlayer // Set the new player
        print("👉 New player instance set.")

        // --- Check Player Readiness ---
        do {
            print("⏳ Waiting for player to become ready (timeout: \(playerReadyTimeout)s)...")

            // Use the withTimeout helper, passing the waitForPlayerReady function as the operation
            try await withTimeout(seconds: playerReadyTimeout) {
                // The operation to perform within the timeout:
                try await self.waitForPlayerReady(player: newPlayer)
            }

            // --- Player Ready ---
            // If withTimeout completes without throwing, the player is ready
            print("✅ Player is ready.")
            // Proceed to the next stage of sync setup
            await continueSync(with: newPlayer)

        } catch let timeoutError as TimeoutError {
            // --- Handle Timeout Error ---
            print("❌ \(timeoutError.localizedDescription)") // Use the error's description
            // Update observable error on main thread
            self.lastError = timeoutError // Store the specific timeout error
            // Cleanup player state as it failed to get ready
            await cleanup(level: .light)

        } catch {
            // --- Handle Other Errors (e.g., player failed) ---
            print("❌ Player failed to become ready: \(error.localizedDescription)")
            // Update observable error on main thread
            self.lastError = error // Store the specific error from waitForPlayerReady
            // Cleanup player state
            await cleanup(level: .light)
        }
    }
    
    @MainActor // KVO setup/invalidation needs main actor
    private func waitForPlayerReady(player: AVPlayer) async throws {
        // If already ready, return immediately
        if player.status == .readyToPlay {
            print("✅ Player already ready.")
            return
        }
        // If already failed, throw immediately
        if player.status == .failed {
            print("❌ Player already failed.")
            throw player.error ?? VideoSyncError.playerNotReady // Throw the player's error if available
        }

        // --- KVO Setup ---
        // Declare observer variable outside the continuation closure but within this function's scope
        var statusObservation: NSKeyValueObservation?

        // Use defer to guarantee cleanup happens when this scope exits
        // Ensure it runs on the MainActor because invalidate() interacts with KVO
        defer {
            Task { @MainActor in
                 print("🧹 Ensuring player status observer is invalidated via defer.")
                 statusObservation?.invalidate()
            }
        }

        // Use continuation to bridge KVO callback
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Flag to prevent resuming multiple times stays local to this closure
            var didResume = false

            print("⏳ Observing player status for .readyToPlay...")
            statusObservation = player.observe(\.status, options: [.new, .initial]) { observedPlayer, _ in
                // Check flag and player instance just in case
                // Also check if the continuation might have already finished (though didResume should cover this)
                guard !didResume, observedPlayer === player else { return }

                switch observedPlayer.status {
                case .readyToPlay:
                    print("✅ Player became ready via KVO.")
                    // No need to invalidate here, defer handles it.
                    didResume = true
                    continuation.resume(returning: ()) // Signal success (Void)
                case .failed:
                    print("❌ Player failed while observing: \(observedPlayer.error?.localizedDescription ?? "Unknown error")")
                    // No need to invalidate here, defer handles it.
                    didResume = true
                    continuation.resume(throwing: observedPlayer.error ?? VideoSyncError.playerNotReady)
                case .unknown:
                    print("❓ Player status changed to unknown while observing.")
                    // Keep observing
                @unknown default:
                    // Keep observing
                    break
                }
            }
            // If the player status was *already* ready/failed when observe started,
            // KVO might call the closure immediately with .initial option.
            // The didResume flag prevents double resumes.
            // If the initial status is unknown, it will wait for a change.
        }
        // If the continuation resumes (returns or throws), the defer block executes.
        // If the Task running this `await` is cancelled, the continuation is implicitly abandoned,
        // the scope exits, and the defer block executes.
    }
    

    @MainActor // Ensure player interactions happen on main thread
    private func continueSync(with player: AVPlayer) async {
         print("✅ Player is ready, continuing sync...")

         // 1️⃣ Add a periodic time observer to track playback time
         setupTimeObservation(player)
         print("⏱️ Time observation setup complete for new player")

         // 2️⃣ Ensure Firebase playState listener is active
         if !isPlayStateListenerActive {
             print("🔥 Setting up new Firebase playState listener")
             setupVideoSync() // This sets up the listener but doesn't wait for initial data
         } else {
             print("🔄 Reusing existing Firebase playState listener")
         }

         // 3️⃣ Apply initial state (Snapshot > Host default)
         // Use a Task to handle the async seek and potential delay
         Task { @MainActor in // Ensure player ops are on main actor
             if let snapshot = currentSnapshot {
                 print("📸 Applying snapshot - Position: \(snapshot.position), Playing: \(snapshot.isPlaying)")
                 await player.seek(
                     to: CMTime(seconds: snapshot.position, preferredTimescale: 1000),
                     toleranceBefore: .zero,
                     toleranceAfter: .zero
                 )
                 print("✅ Initial seek from snapshot complete")

                 // Delay slightly before setting play state after seek for stability
                 try? await Task.sleep(for: .milliseconds(100))
                 if snapshot.isPlaying {
                      player.play()
                      print("▶️ Resuming playback from snapshot")
                 } else {
                      player.pause() // Ensure paused if snapshot indicates
                      print("⏸️ Ensuring paused state from snapshot")
                 }
                 clearSnapshot() // Snapshot has been applied
             } else if isHost {
                 // If host and no snapshot, maybe *start* playing or use current Firestore state?
                 // Let's assume host wants to start playing if joining fresh.
                 print("👑 Host joining/starting: Setting initial play state to playing at 0")
                 // Set local state and push to Firestore
                 await updateLocalPlayState(isPlaying: true, position: self.currentTime) // Use current time (likely 0)
                 await updateFirestorePlayState() // Push this state
                 player.play() // Start the player
             } else {
                 // Non-host, no snapshot: Rely purely on Firestore listener to provide state.
                 // It might take a moment. Player should start paused.
                 print("👤 Non-host joining: Waiting for Firestore state.")
                 player.pause()
             }
         }

         print("✅ Sync initialization process started.")
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
    // Needs to run on MainActor because it interacts with player
    @MainActor
    func handlePlayPause(isPlaying desiredPlayState: Bool) async {
        print("⏯️ handlePlayPause called with isPlaying: \(desiredPlayState)")
        guard let player = currentPlayer else {
            print("⚠️ Cannot handle play/pause: No player.")
            return
        }

        // --- 1. Update Player ---
        // Only change player state if it's different from desired state
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
        // Check if internal state needs updating (player might take time to react)
        if isPlayingState != desiredPlayState {
                await updateLocalPlayState(isPlaying: desiredPlayState, position: player.currentTime().seconds)
        }

        // --- 3. Update Firestore (if Host) ---
        if isHost {
            // Use the updated local state (currentTime updated by updateLocalPlayState)
            await updateFirestorePlayState()
        }
    }

    // MARK: - State Updates (Local & Firestore)

    // Updates observable properties, MUST be called on MainActor
    @MainActor
    private func updateLocalPlayState(isPlaying: Bool, position: Double) {
        // Only update if changed to avoid unnecessary @Observable triggers
        var changed = false
        if self.isPlayingState != isPlaying {
            self.isPlayingState = isPlaying
            print("🔄 Updated local isPlayingState: \(self.isPlayingState)")
            changed = true
        }
        // Always update currentTime locally when state changes
        // Use a slight threshold to avoid jitter? Maybe not needed if driven by observer/events.
        // if abs(self.currentTime - position) > 0.1 { // Optional threshold
             self.currentTime = position
             // print("🔄 Updated local currentTime: \(self.currentTime)") // Can be noisy
        // }

        // If change occurred, maybe notify delegates or trigger other actions
        if changed {
            // Example: Maybe update snapshot if transitioning?
        }
    }

    // Pushes the current local state (`isPlayingState`, `currentTime`) to Firestore
    // Should only be called by the host. Can run async.
    private func updateFirestorePlayState(forceUpdate: Bool = false) async {
        guard isHost, let syncRef = getBasePath() else {
            print("failing here")
            // print("🚫 Not host or no sync path, skipping Firestore update.") // Can be noisy
            return
        }
        print("syncRef")
        print(syncRef)
        // --- Debounce Firestore writes ---
        let now = Date()
        if !forceUpdate, let lastUpdate = lastSyncUpdate, now.timeIntervalSince(lastUpdate) < 1.5 { // 1.5 second debounce
            // print("🔄 Skipping Firestore write due to debounce") // Can be noisy
            return
        }
        lastSyncUpdate = now

        // --- Prepare Data ---
        // Generate a unique ID for this update to prevent echoes
        let updateId = UUID().uuidString
        let data: [String: Any] = [
            "isPlaying": isPlayingState,
            "playbackPosition": currentTime,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": updateId // Include the unique ID
        ]

        // --- Perform Firestore Write ---
        print("🔥 Host pushing state to Firestore: isPlaying=\(isPlayingState), pos=\(String(format: "%.2f", currentTime))")
        do {
            try await syncRef.document("playState").setData(data, merge: true)
            print("✅ Firestore playState updated successfully.")
            // Store the ID of the update we just sent
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
        print("🖥️ Applying server state: isPlaying=\(isPlaying), pos=\(String(format: "%.2f", seconds))")

        guard let player = currentPlayer else {
            print("❌ No player available to apply server state.")
            return
        }

        // --- Sync Playback Position ---
        let localTime = player.currentTime().seconds
        let drift = abs(localTime - seconds)

        // Use Task for async seek operation
        Task { @MainActor in // Ensure player ops are on main actor
            if drift > syncThreshold {
                print("⏱️ Large desync (\(String(format: "%.2f", drift))s). Seeking to \(String(format: "%.2f", seconds))...")
                await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000),
                                  toleranceBefore: .zero, toleranceAfter: .zero)
                print("✅ Seek completed.")
                // After seeking, ensure the play state matches server immediately
                if isPlaying && player.timeControlStatus != .playing {
                     player.play()
                 } else if !isPlaying && player.timeControlStatus != .paused {
                     player.pause()
                 }

            } else if drift > 0.2 { // Small drift threshold (e.g., 200ms)
                // Optional: Smooth correction using rate adjustment (can be tricky)
                // For simplicity, small drifts might be ignored or handled by minor seek if needed
                print("ℹ️ Small desync (\(String(format: "%.2f", drift))s). Monitoring.")
                // Or perform a small seek:
                // await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000),
                //                   toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) // Less precise seek

                 // Ensure play state matches even with small drift
                 if isPlaying && player.timeControlStatus != .playing {
                      player.play()
                  } else if !isPlaying && player.timeControlStatus != .paused {
                      player.pause()
                  }

            } else {
                // In sync position-wise, just ensure play state matches
                if isPlaying && player.timeControlStatus != .playing {
                     print("▶️ Server state is Playing, starting player.")
                     player.play()
                 } else if !isPlaying && player.timeControlStatus != .paused {
                     print("⏸️ Server state is Paused, pausing player.")
                     player.pause()
                 }
            }
        } // End Task

        // Update local state (already done in the listener callback before calling this)
        // await updateLocalPlayState(isPlaying: isPlaying, position: seconds) // No - causes loop if called here

        print("✅ Server state application process finished.")
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
        let wasWithinTime = self.isWithinEventTime // Read needs to be safe if accessed across threads
        updateEventTimeStatus() // Updates observable property

        Task { @MainActor [weak self] in // Read isWithinEventTime safely on main thread
             guard let self = self else { return }
             if wasWithinTime && !self.isWithinEventTime {
                 print("⏱️ Event time ended. Cleaning up...")
                 // Perform full cleanup asynchronously
                 Task { [weak self] in
                     await self?.cleanup(level: .full)
                 }
                 // Optionally dismiss UI immediately
                 self.dismissImmersiveSpace?()
                 // Consider dismissing windows too
             }
         }
    }

    // Updates the observable isWithinEventTime property
    @MainActor                    // ← run entirely on the main actor
    private func updateEventTimeStatus() {
        guard let event = event else {
            isWithinEventTime = false
            return
        }

        let now = Date()
        let inTime = (event.date ... event.end).contains(now)

        if isWithinEventTime != inTime {
            isWithinEventTime = inTime
            if !inTime { currentPlayer?.pause() }
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
                    "lastActive": FieldValue.serverTimestamp(),
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
            print("❌ Error querying potential hosts: \(error.localizedDescription)")
            // Still fall through to try the transaction — worst‑case we’ll mark inactive.
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
                        "lastActive": FieldValue.serverTimestamp(),
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
                    "lastActive": FieldValue.serverTimestamp(),
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
            print("❌ Error during becomeHost transaction: \(error.localizedDescription)")
            Task { await MainActor.run { self.lastError = VideoSyncError.firestoreError(error.localizedDescription); self.isHost = false } }
            return false
        }
    }

    // Initializes room state if needed (e.g., creates initial documents). Async.
    private func initializeRoom() async -> Bool {
         print("🏠 Initializing video sync room...")
         guard let syncRef = getBasePath() else {
             print("❌ Failed to get Firestore path for room initialization")
             return false
         }

         do {
             // Check if core documents (e.g., 'host') exist.
             // Use a more reliable check than just activeViewers count.
             let hostDocRef = syncRef.document("host")
             let hostDoc = try await hostDocRef.getDocument()

             if !hostDoc.exists {
                 print("🆕 Host document doesn't exist. Creating initial room state...")
                 // Use a batch write for initial setup
                 let batch = db.batch()

                 // Host doc
                 batch.setData([
                     "hostId": "", // Initially no host, election will occur
                     "timestamp": FieldValue.serverTimestamp(),
                     "status": "inactive" // Start inactive until claimed
                 ], forDocument: hostDocRef)

                 // Play state doc
                 let playStateDoc = syncRef.document("playState")
                 batch.setData([
                     "isPlaying": false, // Start paused
                     "playbackPosition": 0.0,
                     "updatedAt": FieldValue.serverTimestamp(),
                     "updateId": UUID().uuidString
                 ], forDocument: playStateDoc)

                 // Presence doc (parent, collection created on demand)
                 let presenceDoc = syncRef.document("presence")
                 batch.setData([
                     "lastUpdated": FieldValue.serverTimestamp()
                     // activeViewerCount is implicit from collection size
                 ], forDocument: presenceDoc)

                 // Commit batch
                 try await batch.commit()
                 print("✅ Initial room documents created.")

                 // Now attempt to become the host since room was just created
                 let becameHost = await becomeHost()
                 // Register presence *after* attempting to become host
                 await registerPresence()
                 return true // Room initialized (even if didn't become host)

             } else {
                 print("✅ Room documents already exist.")
                 // Ensure host status is correct (maybe another user initialized but crashed?)
                 // If hostId is empty or status inactive, try to become host or elect
                 if let hostData = hostDoc.data(),
                    let hostId = hostData["hostId"] as? String,
                    let status = hostData["status"] as? String,
                    (hostId.isEmpty || status != "active") {
                     print("ℹ️ Existing host document is inactive/empty. Attempting to claim/elect host.")
                     _ = await becomeHost() // Try to become host
                 }
                 // Always register presence even if room exists
                 await registerPresence()
                 return true
             }
         } catch {
             print("❌ Error initializing room: \(error.localizedDescription)")
             Task { await MainActor.run { self.lastError = VideoSyncError.firestoreError(error.localizedDescription) } }
             return false
         }
     }


    // MARK: - View State Management

    // Should be called on MainActor if it triggers UI/player changes
    @MainActor
    func switchToView(_ state: ViewState) {
         print("🔄 Switching view state to: \(state)")
         guard currentViewState != state else {
             print("⚠️ Already in view state: \(state). No action needed.")
             return
         }

         // Store snapshot before changing state if leaving a view with a player
         if let player = currentPlayer {
             // Get current time accurately from player
             let currentPosition = player.currentTime().seconds
             let isCurrentlyPlaying = player.timeControlStatus == .playing
             print("📸 Storing snapshot before view switch - Pos: \(String(format: "%.2f", currentPosition)), Playing: \(isCurrentlyPlaying)")
             currentSnapshot = SyncSnapshot(position: currentPosition, isPlaying: isCurrentlyPlaying)

             // Pause the player when switching away? Optional, depends on UX.
             // player.pause()
             // handlePlayPause(isPlaying: false) // Update Firestore if host

             // Remove time observer from the player associated with the old view
             removeTimeObserverIfNeeded(from: player)
             // Decide based on cleanup level needed for the switch
             // Setting player to nil depends if the *same instance* will be reused
             // self.currentPlayer = nil // Maybe only do this in full cleanup?
         }

         // Update the view state (Observable, needs main thread)
         self.currentViewState = state

         // Perform actions based on new state (e.g., dismiss/open windows)
         // These dismiss/open calls likely need to happen on main thread too
         switch state {
         case .movieWindow:
             print("➡️ Entering Movie Window state")
             dismissImmersiveSpace?() // Should be main thread safe
             dismissWindow?("immersiveRelatedWindow") // Example
         case .immersive:
             print("➡️ Entering Immersive state")
             dismissWindow?("movieWindow") // Should be main thread safe
             // Immersive view will call startSync when it appears
         case .none:
             print("➡️ Entering None state (likely during cleanup)")
             // Dismiss relevant UI
         }

         print("✅ View state switch complete: \(state)")
     }

     // Should be called on MainActor
     @MainActor
     func clearSnapshot() {
         print("🗑️ Clearing playback snapshot")
         currentSnapshot = nil
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

    private func cleanupListeners() {
         print("🧹 Cleaning up \(listeners.count) Firestore listeners...")
         listeners.forEach { $0?.remove() }
         listeners.removeAll()
         isPlayStateListenerActive = false // Mark listener as inactive
         print("✅ Listeners removed.")
     }

    private func cleanupTimers() {
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

    private func getBasePath() -> CollectionReference? {
        // Make sure access to eventId is safe if called from bg thread
        guard let currentEventId = self.eventId else {
            Task { await MainActor.run { self.lastError = VideoSyncError.missingEventId } }
            print("❌ getBasePath() failed: Missing event ID")
            return nil
        }

        
        // Date formatting is thread safe
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd-yyyy"
            formatter.timeZone = TimeZone(identifier: "EST")
            return formatter
        }()
        let dateString = dateFormatter.string(from: Date())

        // Path construction is safe
        let path = "Public Rooms/\(dateString)/Events/\(currentEventId)/sync"
        print("path")
        print(path)
        // print("📂 Firestore base path: \(path)") // Can be noisy
        return db.collection(path)
    }

    // Simple wrapper for timeout logic
    // Helper for running an async operation with a timeout.
    // Throws TimeoutError if the operation takes too long,
    // or rethrows any error thrown by the operation itself.
    // Put this near the top of the file (or inside the class, but NOT inside a function).
    private struct UnexpectedTimeoutCompletion: Error {}


    // Simple wrapper for timeout logic
    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {

        try await withThrowingTaskGroup(of: T.self) { group in
            // 1) real work
            group.addTask { try await operation() }

            // 2) timeout
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimeoutError(duration: seconds)
            }

            guard let result = try await group.next() else {
                throw UnexpectedTimeoutCompletion()   // <-- now refers to the file‑scoped type
            }

            group.cancelAll()
            return result
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
