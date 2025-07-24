import XCTest
@testable import Movie_Theater_Experience // Make sure this is your app's module name
import FirebaseCore
import FirebaseFirestore
import AVFoundation // Import for AVPlayer

// import FirebaseFirestoreSwift // Keep if you use Codable features directly in tests

// Ensure your CalendarEvent struct is accessible here
// It should be available via @testable import Movie_Theater_Experience

class VideoSyncServiceTests: XCTestCase {

    var service: VideoSyncService!
    // This mockFirestore instance is used by your test helper (createTestEventInFirestore)
    // and for direct assertions in your tests. It MUST point to the emulator.
    var mockFirestore: Firestore!
    static let firestoreHost = "localhost"
    static let firestorePort = 8080

    // Helper to get a properly formatted date string for paths
    private func formattedDateForPath(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        formatter.timeZone = TimeZone(identifier: "EST") // Match your service's timezone
        return formatter.string(from: date)
    }

    // Helper to get project ID for clearing data
    private func getFirebaseProjectId() -> String {
        guard let options = FirebaseApp.app()?.options, let projectId = options.projectID else {
            XCTFail("Firebase Project ID not found. Ensure FirebaseApp.configure() has been called and GoogleService-Info.plist is correct for the test target.")
            return "YOUR_PROJECT_ID_FALLBACK" // Fallback
        }
        return projectId
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        // 1. Configure FirebaseApp if it hasn't been.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        // 2. Create and configure self.mockFirestore for direct test interactions with the emulator.
        let settings = FirestoreSettings()
        settings.host = "\(VideoSyncServiceTests.firestoreHost):\(VideoSyncServiceTests.firestorePort)"
        settings.isSSLEnabled = false
        settings.isPersistenceEnabled = false // Crucial for test isolation

        self.mockFirestore = Firestore.firestore() // Create the instance for the test class
        self.mockFirestore.settings = settings     // Apply emulator settings to it
        print("🧪 VideoSyncServiceTests: self.mockFirestore configured for emulator at \(settings.host)")

        // 3. Prepare VideoSyncService to use its own emulator-configured instance.
        VideoSyncService.MOCK_prepareForTesting(
            emulatorHost: VideoSyncServiceTests.firestoreHost,
            emulatorPort: VideoSyncServiceTests.firestorePort
        )
        service = VideoSyncService.shared // This will now return the mock-prepared instance

        print("🧪 VideoSyncServiceTests: setUpWithError completed. Both self.mockFirestore and service.db should target the emulator.")
    }

    override func tearDownWithError() throws {
        print("🧹 VideoSyncServiceTests: tearDownWithError - Starting service instance cleanup...")

        // Explicitly cleanup listeners and state for the current service instance
        // BEFORE clearing emulator data. This prevents the old instance's listeners
        // from reacting to the data wipe.
        if let serviceInstance = self.service {
            let cleanupExpectation = self.expectation(description: "Service Instance Cleanup Before Data Deletion")
            Task {
                // Using .full cleanup ensures listeners are removed and state is reset.
                await serviceInstance.cleanup(level: .full)
                cleanupExpectation.fulfill()
            }
            wait(for: [cleanupExpectation], timeout: 5.0) // Adjust timeout if needed
        }
        
        print("🧹 VideoSyncServiceTests: Starting Firestore data cleanup...")
        let expectation = self.expectation(description: "Clear Firestore Emulator Data")
        let projectId = getFirebaseProjectId()

        if projectId == "YOUR_PROJECT_ID_FALLBACK" {
            print("⚠️ WARNING: Using fallback Project ID for emulator cleanup.")
        }
        let clearUrlString = "http://\(VideoSyncServiceTests.firestoreHost):\(VideoSyncServiceTests.firestorePort)/emulator/v1/projects/\(projectId)/databases/(default)/documents"
        guard let clearUrl = URL(string: clearUrlString) else {
            XCTFail("Failed to create clear emulator URL for project ID: \(projectId)")
            expectation.fulfill(); try super.tearDownWithError(); return
        }
        print("🧹 Clearing emulator data using URL: \(clearUrlString)")
        var request = URLRequest(url: clearUrl)
        request.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { print("⚠️ Error clearing Firestore emulator: \(error.localizedDescription)") }
            else if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 { print("✅ Firestore Emulator data cleared successfully.") }
                else { print("⚠️ Error clearing Firestore emulator: Status \(httpResponse.statusCode). Body: \(data.flatMap { String(data: $0, encoding: .utf8) } ?? "N/A")") }
            }
            expectation.fulfill()
        }.resume()
        wait(for: [expectation], timeout: 10.0) // Keep this wait for the HTTP DELETE
        print("🧹 VideoSyncServiceTests: Firestore data cleanup finished.")

        VideoSyncService.MOCK_finishTesting() // Static cleanup for the singleton factory
        self.service = nil // Release the instance from the test case
        mockFirestore = nil
        try super.tearDownWithError()
    }
    
    /// Returns a URL for a resource that lives in the test bundle.
    func urlInTestBundle(named name: String, ext: String) -> URL {
        // `self` is the current XCTestCase subclass
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            fatalError("⚠️ \(name).\(ext) not found in test bundle – " +
                       "check Target Membership")
        }
        return url
    }

    

    // Helper function to create a CalendarEvent in Firestore for testing
    func createTestEventInFirestore(eventId: String,
                                    userId: String,
                                    existingHostId: String?,
                                    eventDate: Date,
                                    firestore: Firestore) async throws {
        let dateString = formattedDateForPath(date: eventDate)
        let basePath = "Public Rooms/\(dateString)/Events/\(eventId)/sync"

        let playStateDocRef = firestore.document("\(basePath)/playState")
        try await playStateDocRef.setData([
            "isPlaying": false, "playbackPosition": 0.0,
            "updatedAt": FieldValue.serverTimestamp(), "updateId": UUID().uuidString
        ])
        // print("🧪 Helper: Created playState document at \(playStateDocRef.path)") // Can be noisy

        if let hostIdToSet = existingHostId {
            let hostDocRef = firestore.document("\(basePath)/host")
            try await hostDocRef.setData([
                "hostId": hostIdToSet, "status": "active",
                "timestamp": FieldValue.serverTimestamp(), "lastUpdate": FieldValue.serverTimestamp()
            ])
            // print("🧪 Helper: Created host document at \(hostDocRef.path) with host: \(hostIdToSet)")

            let presenceDocRef = firestore.document("\(basePath)/presence/activeViewers/\(hostIdToSet)")
            try await presenceDocRef.setData([
                "userId": hostIdToSet, "lastSeen": FieldValue.serverTimestamp(),
                "joined": FieldValue.serverTimestamp(), "status": "active", "isHost": true
            ])
            // print("🧪 Helper: Created presence for existing host \(hostIdToSet) at \(presenceDocRef.path)")
        } else {
             // print("🧪 Helper: No existing host specified for pre-creation.")
        }
        // print("🧪 Helper: Database setup complete for event \(eventId).")
    }
    
    // --- Test Cases ---

    @MainActor // Methods interacting with AVPlayer should be on main actor
        func testStartSync_whenNotInEventTime_failsEarly() async throws {
            // ARRANGE
            let eventId = "testEventStartSyncPast"
            let userId = "testUserStartSync"
            let now = Date()
            let pastStartDate = now.addingTimeInterval(-3600 * 2)
            let pastEndDate = now.addingTimeInterval(-3600 * 1)
            let passedEvent = CalendarEvent(id: eventId, title: "Past Event for StartSync", date: pastStartDate, end: pastEndDate, description: "Past event.", color: 1, videoURL: "http://example.com/video.mp4")

            // Configure sync (it will set isWithinEventTime to false)
            _ = await service.configureSync(eventId: eventId, userId: userId, event: passedEvent)
            XCTAssertFalse(service.isWithinEventTime, "Precondition: Service should not be within event time.")

            let dummyPlayer = AVPlayer() // Player won't actually be used

            // ACT
            print("🧪 testStartSync_whenNotInEventTime: Calling startSync...")
            await service.startSync(with: dummyPlayer)
            print("🧪 testStartSync_whenNotInEventTime: startSync completed. lastError: \(String(describing: service.lastError))")

            // ASSERT
            XCTAssertNotNil(service.lastError, "lastError should be set when trying to start sync outside event time.")
            XCTAssertTrue(service.lastError is VideoSyncError, "Error should be a VideoSyncError.")
            if let syncError = service.lastError as? VideoSyncError {
                XCTAssertEqual(syncError, .syncConfigurationFailed, "Expected .syncConfigurationFailed error.")
            }
            XCTAssertNil(service.currentPlayer, "currentPlayer should remain nil as sync should not have proceeded.")
        }
    
    @MainActor
        func testStartSync_withFailingPlayerItem_resultsInErrorOrTimeout() async throws {
            // ARRANGE
            let eventId = "testEventPlayerFailsItem"
            let userId = "testUserPlayerFailsItem"
            let testDate = Date()
            let currentEvent = CalendarEvent(id: eventId, title: "Player Fail Item Test", date: testDate, end: testDate.addingTimeInterval(3600), description: "Event for player item fail.", color: 1, videoURL: "placeholder-for-event.mp4")

            let configSuccess = await service.configureSync(eventId: eventId, userId: userId, event: currentEvent)
            XCTAssertTrue(configSuccess, "Sync configuration should succeed.")
            XCTAssertTrue(service.isWithinEventTime, "Service should be within event time.")

            // Use a URL that is syntactically valid but points to a non-existent resource
            // or a resource that AVPlayer cannot handle. An invalid scheme is good.
            guard let invalidURL = URL(string: "completely-invalid-scheme://nonexistent-domain/nonexistent.mp4") else {
                XCTFail("Could not create invalid scheme URL"); return
            }
            let failingItem = AVPlayerItem(url: invalidURL)
            let player = AVPlayer(playerItem: failingItem)
            
            print("🧪 testStartSync_withFailingPlayerItem: Player initialized with invalid scheme URL.")
            // Give player item a brief moment to attempt loading and potentially update its status.
            // This helps ensure that when waitForPlayerReady is called, the item's state is more likely to be terminal.
            try await Task.sleep(for: .milliseconds(500)) // Increased delay slightly

            print("🧪 Player status before startSync: \(player.status.rawValue), Item status: \(player.currentItem?.status.rawValue ?? -99), Item error: \(String(describing: player.currentItem?.error))")
            
            // ACT
            print("🧪 testStartSync_withFailingPlayerItem: Calling startSync...")
            await service.startSync(with: player)
            print("🧪 testStartSync_withFailingPlayerItem: startSync completed. lastError: \(String(describing: service.lastError))")

            // ASSERT
            XCTAssertNotNil(service.lastError, "lastError should be set due to player item failure or timeout.")
            
            var foundExpectedErrorType = false
            if let syncError = service.lastError as? VideoSyncError, syncError == .playerNotReady {
                foundExpectedErrorType = true
                print("✅ Identified VideoSyncError.playerNotReady.")
            } else if service.lastError is TimeoutError {
                foundExpectedErrorType = true
                print("✅ Identified a TimeoutError. Player likely remained in .unknown status or did not fail fast enough to be caught by KVO as .failed.")
            } else if let nsError = service.lastError as? NSError {
                // Check for common AVFoundation error domains/codes if possible
                print("✅ Identified an NSError (Code: \(nsError.code), Domain: \(nsError.domain)), likely from AVFoundation: \(nsError.localizedDescription)")
                if nsError.domain == AVFoundationErrorDomain { // More specific check
                     foundExpectedErrorType = true
                } else {
                     // If it's an NSError but not AVFoundation, it might still be an acceptable failure
                     // For this test, any non-nil error after trying to load a bad item is a pass for the XCTAssertNotNil.
                     // The XCTAssertTrue below will catch if it's not one of the expected types.
                     print("ℹ️ NSError was not from AVFoundationErrorDomain, but an error was present.")
                     foundExpectedErrorType = true // Consider any NSError a valid failure path for this test's purpose
                }
            }
            
            XCTAssertTrue(foundExpectedErrorType, "Expected .playerNotReady, TimeoutError, or an AVFoundation NSError, but got \(String(describing: service.lastError)) of type \(String(describing: type(of: service.lastError))).")
            XCTAssertNotNil(service.currentPlayer, "Current player should have been set by startSync, even if it failed to become ready.")
        }

    @MainActor
    func testStartSync_withNonReadyingPlayer_timesOut() async throws { // Consider renaming to reflect actual error
        // ARRANGE
        let eventId = "testEventPlayerEmpty" // Renamed for clarity
        let userId = "testUserPlayerEmpty"
        let testDate = Date()

        let currentEvent = CalendarEvent(id: eventId, title: "Player Empty Test", date: testDate, end: testDate.addingTimeInterval(3600), description: "Event for empty player.", color: 1, videoURL: "http://example.com/video.mp4")

        let configSuccess = await service.configureSync(eventId: eventId, userId: userId, event: currentEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed.")
        XCTAssertTrue(service.isWithinEventTime, "Service should be within event time.")

        let nonReadyingPlayer = AVPlayer() // An empty player (no item)

        print("🧪 testStartSync_withNonReadyingPlayer: Calling startSync with an empty player...")
        // ACT
        await service.startSync(with: nonReadyingPlayer)
        print("🧪 testStartSync_withNonReadyingPlayer: startSync completed. lastError: \(String(describing: service.lastError))")

        // ASSERT
        XCTAssertNotNil(service.lastError, "lastError should be set.")
        // Expect .playerNotReady because waitForPlayerReady now correctly detects no item
        XCTAssertTrue(service.lastError is VideoSyncError, "Error should be a VideoSyncError, but was \(String(describing: type(of: service.lastError))).")
        if let syncError = service.lastError as? VideoSyncError {
            XCTAssertEqual(syncError, .playerNotReady, "Expected .playerNotReady for an empty player, but got \(syncError)")
        }
        // currentPlayer might still be set by startSync, even if it couldn't be made ready.
        XCTAssertNotNil(service.currentPlayer, "Current player should have been set by startSync.")
    }
    
    
    func testConfigureSync_eventTimeHasPassed_failsConfiguration() async throws {
        // ARRANGE
        let eventId = "testEventPassed"
        let userId = "testUserForPassedEvent"
        let now = Date()
        let pastStartDate = now.addingTimeInterval(-3600 * 2) // Event started 2 hours ago
        let pastEndDate = now.addingTimeInterval(-3600 * 1)   // Event ended 1 hour ago

        let passedEvent = CalendarEvent(
            id: eventId,
            title: "Event That Has Passed",
            date: pastStartDate,
            end: pastEndDate,
            description: "This event is in the past.",
            color: 3,
            videoURL: "https://example.com/passed_video.mp4"
        )

        print("🧪 testConfigureSync_eventTimeHasPassed: Event start: \(pastStartDate), Event end: \(pastEndDate)")

        // ACT
        print("🧪 testConfigureSync_eventTimeHasPassed: Calling configureSync...")
        let success = await service.configureSync(eventId: eventId, userId: userId, event: passedEvent)
        print("🧪 testConfigureSync_eventTimeHasPassed: configureSync returned \(success)")

        // ASSERT
        XCTAssertFalse(success, "configureSync should return false for an event that has already passed.")
        XCTAssertFalse(service.isWithinEventTime, "isWithinEventTime should be false for a passed event.")
        XCTAssertNotNil(service.lastError, "lastError should be set.")
        
        XCTAssertTrue(service.lastError is VideoSyncError, "Error should be a VideoSyncError.")
        if let syncError = service.lastError as? VideoSyncError {
            switch syncError {
            case .syncConfigurationFailed:
                break // This is the expected error
            default:
                XCTFail("Expected .syncConfigurationFailed error, but got \(syncError)")
            }
        }
        
        // Properties ARE set before the time check, so assert their values
        XCTAssertEqual(service.eventId, eventId, "eventId should have been set before the time check failed.")
        XCTAssertEqual(service.userId, userId, "userId should have been set before the time check failed.")
        XCTAssertNotNil(service.event, "event object should have been set.")
        if service.event != nil { // Further check if event was set correctly
             XCTAssertEqual(service.event?.id, eventId, "Stored event ID should match.")
        }
        XCTAssertFalse(service.isHost, "isHost should remain false.")
        XCTAssertEqual(service.activeViewerCount, 0, "activeViewerCount should be 0 as sync failed early.")
    }
    
    // Test Case 3: Verify listeners are active after successful configuration
        func testConfigureSync_success_listenersAreActive() async throws {
            // ARRANGE
            let eventId = "testEventListeners"
            let userId = "testUserListenerCheck"
            let otherUserId = "otherTestUser"
            let testDate = Date()
            let calendarEvent = CalendarEvent(
                id: eventId, title: "Listener Test Event", date: testDate,
                end: testDate.addingTimeInterval(3600), description: "Testing listener activation.",
                color: 5, videoURL: "https://example.com/listener_video.mp4"
            )

            // ACT: Configure sync - user should become host
            let configSuccess = await service.configureSync(eventId: eventId, userId: userId, event: calendarEvent)
            XCTAssertTrue(configSuccess, "Initial sync configuration should succeed.")
            try await Task.sleep(for: .milliseconds(200)) // Allow initial listeners to attach and state to settle
            XCTAssertTrue(service.isHost, "User should be host after initial config.")
            
            var initialViewerCount = 0
            await MainActor.run { initialViewerCount = service.activeViewerCount } // Read on main
            XCTAssertEqual(initialViewerCount, 1, "Initial viewer count should be 1.")

            // --- Test Presence Listener ---
            print("🧪 Testing Presence Listener: Adding another user...")
            let dateString = formattedDateForPath(date: testDate)
            let presencePathOtherUser = "Public Rooms/\(dateString)/Events/\(eventId)/sync/presence/activeViewers/\(otherUserId)"
            try await self.mockFirestore.document(presencePathOtherUser).setData([
                "userId": otherUserId, "lastSeen": FieldValue.serverTimestamp(),
                "joined": FieldValue.serverTimestamp(), "status": "active", "isHost": false
            ])

            // Poll for activeViewerCount to become 2
            var attempts = 0; let maxAttempts = 50; var countMet = false
            print("🧪 Waiting for activeViewerCount to become 2...")
            while !countMet && attempts < maxAttempts {
                if service.activeViewerCount == 2 { countMet = true; print("✅ activeViewerCount is 2.") }
                else { try await Task.sleep(for: .milliseconds(100)) }
                attempts += 1
            }
            XCTAssertTrue(countMet, "activeViewerCount should become 2 after adding another user. Was \(service.activeViewerCount)")

            print("🧪 Testing Presence Listener: Removing other user...")
            try await self.mockFirestore.document(presencePathOtherUser).delete()
            
            countMet = false; attempts = 0
            print("🧪 Waiting for activeViewerCount to become 1...")
            while !countMet && attempts < maxAttempts {
                if service.activeViewerCount == 1 { countMet = true; print("✅ activeViewerCount is 1.") }
                else { try await Task.sleep(for: .milliseconds(100)) }
                attempts += 1
            }
            XCTAssertTrue(countMet, "activeViewerCount should become 1 after removing the other user. Was \(service.activeViewerCount)")

            // --- Test Host Listener ---
            print("🧪 Testing Host Listener: Changing host in Firestore...")
            let hostDocPath = "Public Rooms/\(dateString)/Events/\(eventId)/sync/host"
            try await self.mockFirestore.document(hostDocPath).setData([
                "hostId": otherUserId, "status": "active", // Make the other user the host
                "timestamp": FieldValue.serverTimestamp(), "lastUpdate": FieldValue.serverTimestamp()
            ])

            var hostStatusChanged = false; attempts = 0
            print("🧪 Waiting for service.isHost to become false...")
            while !hostStatusChanged && attempts < maxAttempts {
                if !service.isHost { hostStatusChanged = true; print("✅ service.isHost is now false.") }
                else { try await Task.sleep(for: .milliseconds(100)) }
                attempts += 1
            }
            XCTAssertTrue(hostStatusChanged, "Service should no longer be host after Firestore update. service.isHost is \(service.isHost)")
        }

        // Test Case 4: Calling configureSync twice resets and reconfigures
    func testConfigureSync_calledTwice_withDifferentValidEvents_resetsAndReconfigures() async throws {
            // ARRANGE - First configuration
            let eventId1 = "eventFirstConfig"
            let userId1 = "userFirstConfig"
            let date1 = Date() // Current time
            let calendarEvent1 = CalendarEvent(id: eventId1, title: "First Event", date: date1, end: date1.addingTimeInterval(3600), description: "First.", color: 1, videoURL: "https://example.com/first.mp4")

            print("🧪 Calling configureSync (1st time)...")
            let success1 = await service.configureSync(eventId: eventId1, userId: userId1, event: calendarEvent1)
            XCTAssertTrue(success1, "First configureSync should succeed.")
            try await Task.sleep(for: .milliseconds(300)) // Allow listeners to settle
            XCTAssertEqual(service.eventId, eventId1)
            XCTAssertEqual(service.userId, userId1)
            XCTAssertTrue(service.isHost, "User1 should be host for the first event.")
            
            var viewerCount1Met = false; var attempts1 = 0
            let expectedCount1 = 1
            print("🧪 Waiting for activeViewerCount to become \(expectedCount1) for first event...")
            while !viewerCount1Met && attempts1 < 30 { if service.activeViewerCount == expectedCount1 { viewerCount1Met = true; print("✅ activeViewerCount is \(expectedCount1) for first event.") } else { try await Task.sleep(for: .milliseconds(100))}; attempts1 += 1 }
            XCTAssertTrue(viewerCount1Met, "Viewer count should be \(expectedCount1) for first event. Was \(service.activeViewerCount)")


            // ARRANGE - Second configuration (DIFFERENT eventId, but also valid NOW)
            let eventId2 = "eventSecondConfig" // Different ID
            let userId2 = "userSecondConfig"
            let date2 = Date() // Also current time, to make it a valid event for configureSync
            let calendarEvent2 = CalendarEvent(id: eventId2, title: "Second Event", date: date2, end: date2.addingTimeInterval(3600), description: "Second.", color: 2, videoURL: "https://example.com/second.mp4")

            // ACT - Second configuration
            print("🧪 Calling configureSync (2nd time) for a different, currently valid event...")
            let success2 = await service.configureSync(eventId: eventId2, userId: userId2, event: calendarEvent2)

            // ASSERT - State reflects the second configuration
            XCTAssertTrue(success2, "Second configureSync with a different valid event should succeed.")
            if let err = service.lastError { XCTFail("lastError should be nil after successful second config, but was \(err.localizedDescription)") }
            
            XCTAssertEqual(service.eventId, eventId2, "eventId should be updated to the second event.")
            XCTAssertEqual(service.userId, userId2, "userId should be updated to the second user.")
            XCTAssertNotNil(service.event, "Event object should be updated.")
            XCTAssertEqual(service.event?.id, eventId2, "Stored event should be the second event.")

            try await Task.sleep(for: .milliseconds(300))
            XCTAssertTrue(service.isHost, "User2 should become host for the new (second) event.")

            var viewerCount2Met = false; var attempts2 = 0
            let expectedCount2 = 1
            print("🧪 Waiting for activeViewerCount to become \(expectedCount2) for the second event...")
            while !viewerCount2Met && attempts2 < 50 {
                if service.activeViewerCount == expectedCount2 { viewerCount2Met = true; print("✅ activeViewerCount is \(expectedCount2) for second event.") }
                else { try await Task.sleep(for: .milliseconds(100)) }
                attempts2 += 1
            }
            XCTAssertTrue(viewerCount2Met, "activeViewerCount should be \(expectedCount2) for the second event (reflecting only userId2). Current: \(service.activeViewerCount)")

            // Verify Firestore for the second event
            // getBasePath uses self.event.date, which is now date2 (today)
            let dateString2 = formattedDateForPath(date: date2)
            let basePath2 = "Public Rooms/\(dateString2)/Events/\(eventId2)/sync"
            let hostDocRef2 = self.mockFirestore.document("\(basePath2)/host")
            let hostDoc2 = try await hostDocRef2.getDocument()
            XCTAssertTrue(hostDoc2.exists, "Host document for the second event should exist.")
            XCTAssertEqual(hostDoc2.data()?["hostId"] as? String, userId2, "HostId for second event should be userId2.")
        }
    

    func testConfigureSync_eventNotYetStarted_failsConfiguration() async throws {
        // ARRANGE
        let eventId = "testEventFuture"
        let userId = "testUserForFutureEvent"
        let now = Date()
        let futureStartDate = now.addingTimeInterval(3600 * 1) // Event starts in 1 hour
        let futureEndDate = now.addingTimeInterval(3600 * 2)   // Event ends in 2 hours

        let futureEvent = CalendarEvent(
            id: eventId,
            title: "Event In The Future",
            date: futureStartDate,
            end: futureEndDate,
            description: "This event has not started yet.",
            color: 4,
            videoURL: "https://example.com/future_video.mp4"
        )
        print("🧪 testConfigureSync_eventNotYetStarted: Event start: \(futureStartDate), Event end: \(futureEndDate)")

        // ACT
        print("🧪 testConfigureSync_eventNotYetStarted: Calling configureSync...")
        let success = await service.configureSync(eventId: eventId, userId: userId, event: futureEvent)
        print("🧪 testConfigureSync_eventNotYetStarted: configureSync returned \(success)")

        // ASSERT
        XCTAssertFalse(success, "configureSync should return false for an event that has not yet started.")
        XCTAssertFalse(service.isWithinEventTime, "isWithinEventTime should be false for a future event.")
        XCTAssertNotNil(service.lastError, "lastError should be set.")

        XCTAssertTrue(service.lastError is VideoSyncError, "Error should be a VideoSyncError.")
        if let syncError = service.lastError as? VideoSyncError {
            switch syncError {
            case .syncConfigurationFailed:
                break // This is the expected error
            default:
                XCTFail("Expected .syncConfigurationFailed error, but got \(syncError)")
            }
        }
        
        // Properties ARE set before the time check, so assert their values
        XCTAssertEqual(service.eventId, eventId, "eventId should have been set before the time check failed.")
        XCTAssertEqual(service.userId, userId, "userId should have been set before the time check failed.")
        XCTAssertNotNil(service.event, "event object should have been set.")
        if service.event != nil { // Further check if event was set correctly
             XCTAssertEqual(service.event?.id, eventId, "Stored event ID should match.")
        }
        XCTAssertFalse(service.isHost, "isHost should remain false.")
        XCTAssertEqual(service.activeViewerCount, 0, "activeViewerCount should be 0 as sync failed early.")
    }
    
    // MARK: - startSync happy-path
    @MainActor
    func testStartSync_playerReadyImmediately_continuesToSyncLogic() async throws {
        // ── Arrange ─────────────────────────────────────────────────────
        let event = makeLiveEvent(id: "readyEvent")
        _ = await service.configureSync(eventId: event.id!, userId: "host", event: event)

        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        try await poll(until: { player.status == .readyToPlay }, timeout: 3)

        // ── Act ─────────────────────────────────────────────────────────
        await service.startSync(with: player)

        // 📡 wait until the async Task in setupVideoSync sets the flag
        try await poll(until: { self.service.isPlayStateListenerActive }, timeout: 2)

        // ── Assert ──────────────────────────────────────────────────────
        XCTAssertNil(service.lastError)
        XCTAssertTrue(service.isPlayStateListenerActive, "Firestore playState listener should be running")
        XCTAssertTrue(service.currentPlayer === player)
    }

    
    // MARK: - snapshot restore
    @MainActor
    func testContinueSync_withSnapshot_playerSeeksAndSetsPlayState() async throws {
        // ── Arrange ─────────────────────────────────────────────────────
        let event = makeLiveEvent(id: "snapshotEvent")
        _ = await service.configureSync(eventId: event.id ?? "test",
                                        userId: "host",
                                        event: event)

        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        try await poll(until: { player.status == .readyToPlay }, timeout: 3)

        // inject snapshot: resume at 5 s and start playing
        let targetPos = 5.0
        service.storePlaybackSnapshot(position: targetPos, isPlaying: true)

        // ── Act (startSync → continueSync) ──────────────────────────────
        await service.startSync(with: player)

        // wait until seek/play finished (<= 2 s on local asset)
        try await poll(until: {
            abs(player.currentTime().seconds - targetPos) < 0.25 &&
            player.timeControlStatus == .playing
        }, timeout: 2)

        // ── Assert ──────────────────────────────────────────────────────
        XCTAssertTrue(abs(player.currentTime().seconds - targetPos) < 0.25,
                      "Player should seek close to snapshot position")
        XCTAssertEqual(player.timeControlStatus, .playing)
        XCTAssertNil(service.currentSnapshot, "Snapshot must be cleared after apply")
    }
    
    
    @MainActor // Interacts with AVPlayer and @Observable properties
    func test11_handlePlayPause_asNonHost_togglesPlayerLocally_doesNotUpdateFirestore() async throws {
        // ARRANGE
        let eventId = "nonHostToggleEvent"
        let hostUserId = "theActualHost"
        let nonHostUserId = "notTheHostUser"
        let liveEvent = makeLiveEvent(id: eventId)
        let testDate = service.event?.date ?? Date() // Use event date for path consistency if available

        // 1. Pre-populate Firestore with an existing host and a playing state
        print("🧪 [Test 11] Setting up initial host and playing state in Firestore...")
        try await createTestEventInFirestore( // This helper should use self.mockFirestore
            eventId: eventId,
            userId: hostUserId, // This is the initial user from createTestEvent...
            existingHostId: hostUserId, // ...making them the host.
            eventDate: testDate,
            firestore: self.mockFirestore // Use the test class's mockFirestore for setup
        )
        // Explicitly set playState to playing by the host
        let playStateRef = self.mockFirestore.collection("Public Rooms/\(formattedDateForPath(date:testDate))/Events/\(eventId)/sync").document("playState")
        let initialHostUpdateId = UUID().uuidString
        try await playStateRef.setData([
            "isPlaying": true,
            "playbackPosition": 5.0, // Start at 5s
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": initialHostUpdateId
        ], merge: true)
        print("🧪 [Test 11] Firestore pre-populated. Host: \(hostUserId), Playing: true, Position: 5.0")

        // 2. Configure service as non-host
        print("🧪 [Test 11] Configuring sync as non-host (\(nonHostUserId))...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: nonHostUserId, event: liveEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed for non-host.")
        try await poll(until: { !self.service.isHost && self.service.activeViewerCount >= 1 }, timeout: 3.0) // >=1 because createTestEvent might add host
        XCTAssertFalse(service.isHost, "Service should NOT be host.")

        // 3. Setup player and start sync. Player should pick up playing state from Firestore.
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        print("🧪 [Test 11] Starting sync with player for non-host...")
        await service.startSync(with: player)

        // Wait for player to be ready and sync to server state (playing at 5s)
        try await poll(until: {
            player.status == .readyToPlay &&
            self.service.isPlayStateListenerActive &&
            abs((player.currentTime().seconds) - 5.0) < self.service.syncThreshold + 0.5 && // Check seek
            player.timeControlStatus == .playing && // Check playing
            self.service.isPlayingState == true
        }, timeout: 5.0)

        XCTAssertTrue(service.isPlayingState, "Service's isPlayingState should be true (from host).")
        XCTAssertEqual(player.timeControlStatus, .playing, "Player should be playing (from host).")
        print("🧪 [Test 11] Initial non-host state: Player playing (synced from host). Proceeding to PAUSE locally.")

        // ACT: Call handlePlayPause to PAUSE (as non-host)
        await service.handlePlayPause(isPlaying: false)

        // ASSERT: Player pauses locally, service state updates, Firestore is NOT updated by this client
        XCTAssertFalse(service.isPlayingState, "Service's isPlayingState should be false after local pause.")
        try await poll(until: { player.timeControlStatus == .paused }, timeout: 1.0)
        XCTAssertEqual(player.timeControlStatus, .paused, "Player should be paused locally.")

        // Verify Firestore was NOT changed by this non-host action
        let playStateSnap = try await self.mockFirestore.document(playStateRef.path).getDocument()
        XCTAssertTrue(playStateSnap.exists, "PlayState document should still exist.")
        XCTAssertEqual(playStateSnap.data()?["isPlaying"] as? Bool, true, "Firestore should STILL indicate playing (host's state).")
        XCTAssertEqual(playStateSnap.data()?["playbackPosition"] as? Double, 5.0, "Firestore position should still be host's last known position.")
        XCTAssertEqual(playStateSnap.data()?["updateId"] as? String, initialHostUpdateId, "Firestore updateId should NOT have changed by non-host.")
        
        print("✅ [Test 11] Completed successfully. Non-host paused locally, Firestore unchanged.")
    }

    @MainActor
    func test10_handlePlayPause_asHost_togglesPlayerAndUpdatesFirestore() async throws {
        // ARRANGE
        let eventId = "hostToggleEvent"
        let userId = "hostUser"
        let liveEvent = makeLiveEvent(id: eventId)

        print("🧪 [Test 10] Configuring sync as host...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: userId, event: liveEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed for host.")
        try await poll(until: { self.service.isHost && self.service.activeViewerCount == 1 }, timeout: 2.0)
        XCTAssertTrue(service.isHost, "Service should be host.")

        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        print("🧪 [Test 10] Starting sync with player...")
        await service.startSync(with: player)
        
        try await poll(until: {
            player.status == .readyToPlay &&
            self.service.isPlayStateListenerActive &&
            player.timeControlStatus == .playing &&
            self.service.isPlayingState == true
        }, timeout: 5.0)

        let playStateRef = try XCTUnwrap(service.getBasePath()?.document("playState"))
        var playStateSnap = try await self.mockFirestore.document(playStateRef.path).getDocument()
        XCTAssertTrue(playStateSnap.exists, "PlayState document should exist after host sync.")
        XCTAssertEqual(playStateSnap.data()?["isPlaying"] as? Bool, true, "Firestore should indicate playing initially by host.")
        let initialUpdateId = playStateSnap.data()?["updateId"] as? String
        XCTAssertNotNil(initialUpdateId, "Initial updateId should be set in Firestore.")

        print("🧪 [Test 10] Initial state: Player playing, Firestore playing. Proceeding to PAUSE.")
        // ACT 1: Call handlePlayPause to PAUSE
        await service.handlePlayPause(isPlaying: false)

        // ASSERT 1
        XCTAssertFalse(service.isPlayingState, "Service's isPlayingState should be false after pausing.")
        try await poll(until: { player.timeControlStatus == .paused }, timeout: 1.0)
        XCTAssertEqual(player.timeControlStatus, .paused, "Player should be paused.")

        playStateSnap = try await self.mockFirestore.document(playStateRef.path).getDocument() // Re-fetch
        XCTAssertEqual(playStateSnap.data()?["isPlaying"] as? Bool, false, "Firestore should be updated to isPlaying: false.")
        XCTAssertNotEqual(playStateSnap.data()?["updateId"] as? String, initialUpdateId, "Firestore updateId should have changed after pause.")
        let pausedUpdateId = playStateSnap.data()?["updateId"] as? String
        XCTAssertNotNil(pausedUpdateId, "Paused updateId should exist.")


        print("🧪 [Test 10] Paused state: Player paused, Firestore paused. Proceeding to PLAY.")
        // ACT 2: Call handlePlayPause to PLAY
        await service.handlePlayPause(isPlaying: true)

        // ASSERT 2
        XCTAssertTrue(service.isPlayingState, "Service's isPlayingState should be true after playing.")
        try await poll(until: { player.timeControlStatus == .playing }, timeout: 1.0)
        XCTAssertEqual(player.timeControlStatus, .playing, "Player should be playing.")

        playStateSnap = try await self.mockFirestore.document(playStateRef.path).getDocument() // Re-fetch
        XCTAssertEqual(playStateSnap.data()?["isPlaying"] as? Bool, true, "Firestore should be updated to isPlaying: true.")
        XCTAssertNotEqual(playStateSnap.data()?["updateId"] as? String, pausedUpdateId, "Firestore updateId should have changed after play.")
        
        print("✅ [Test 10] Completed successfully.")
    }
    
    @MainActor
    func test12_playStateListener_nonHostReceivesPlayCommand_playerStarts() async throws {
        // ARRANGE
        let eventId = "nonHostListenerPlayEvent"
        let hostUserId = "theHostForListenerTest"
        let nonHostUserId = "listenerUserPlay"
        let liveEvent = makeLiveEvent(id: eventId)
        let testDate = service.event?.date ?? Date() // Use event date for path consistency

        // 1. Pre-populate Firestore with an existing host. PlayState initially paused.
        print("🧪 [Test 12] Setting up initial host and PAUSED state in Firestore...")
        try await createTestEventInFirestore(
            eventId: eventId,
            userId: hostUserId, // This user is part of the initial setup via helper
            existingHostId: hostUserId, // Explicitly make them host
            eventDate: testDate,
            firestore: self.mockFirestore
        )
        let playStateDocPath = "Public Rooms/\(formattedDateForPath(date: testDate))/Events/\(eventId)/sync/playState"
        let playStateRef = self.mockFirestore.document(playStateDocPath)
        try await playStateRef.setData([ // Initial state: Paused at 0s
            "isPlaying": false,
            "playbackPosition": 0.0,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": UUID().uuidString
        ], merge: true)

        // 2. Configure service as non-host
        print("🧪 [Test 12] Configuring sync as non-host (\(nonHostUserId))...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: nonHostUserId, event: liveEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed for non-host.")
        try await poll(until: { !self.service.isHost && self.service.activeViewerCount >= 1 }, timeout: 3.0)
        XCTAssertFalse(service.isHost, "Service should NOT be host.")

        // 3. Setup player and start sync. Player should initially be paused (reflecting Firestore).
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        print("🧪 [Test 12] Starting sync with player for non-host...")
        await service.startSync(with: player)

        try await poll(until: { // Wait for initial sync to paused state
            player.status == .readyToPlay &&
            self.service.isPlayStateListenerActive &&
            player.timeControlStatus == .paused &&
            self.service.isPlayingState == false
        }, timeout: 5.0)
        XCTAssertEqual(player.timeControlStatus, .paused, "Player should initially be paused by Firestore state.")
        XCTAssertFalse(service.isPlayingState, "Service should initially be not playing.")
        print("🧪 [Test 12] Non-host initially paused. Ready for Firestore PLAY command.")

        // ACT: Directly write to the playState document in Firestore to simulate host commanding PLAY
        let playCommandUpdateId = UUID().uuidString
        let targetPlayPosition = 10.0
        print("🧪 [Test 12] Simulating host: Writing PLAY (true) and position (\(targetPlayPosition)s) to Firestore...")
        try await playStateRef.setData([
            "isPlaying": true,
            "playbackPosition": targetPlayPosition,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": playCommandUpdateId
        ], merge: true)

        // ASSERT: Service updates local state, player starts playing and seeks.
        try await poll(until: { // Wait for the listener to react and update player
            self.service.isPlayingState == true &&
            player.timeControlStatus == .playing &&
            abs(player.currentTime().seconds - targetPlayPosition) < self.service.syncThreshold + 0.5 // check seek
        }, timeout: 5.0)

        XCTAssertTrue(service.isPlayingState, "Service's isPlayingState should become true.")
        XCTAssertEqual(player.timeControlStatus, .playing, "Player should start playing.")
        XCTAssertEqual(service.currentTime, targetPlayPosition, accuracy: service.syncThreshold + 0.5, "Service currentTime should update to \(targetPlayPosition)s.")
        XCTAssertEqual(player.currentTime().seconds, targetPlayPosition, accuracy: service.syncThreshold + 0.5, "Player should seek to \(targetPlayPosition)s.")
        
        print("✅ [Test 12] Completed: Non-host received PLAY, player started and seeked.")
    }

    @MainActor
    func test13_playStateListener_nonHostReceivesPauseCommand_playerPauses() async throws {
        // ARRANGE
        let eventId = "nonHostListenerPauseEvent"
        let hostUserId = "theHostForListenerTestB"
        let nonHostUserId = "listenerUserPause"
        let liveEvent = makeLiveEvent(id: eventId)
        let testDate = service.event?.date ?? Date()

        // 1. Pre-populate Firestore with an existing host. PlayState initially PLAYING.
        print("🧪 [Test 13] Setting up initial host and PLAYING state in Firestore...")
        try await createTestEventInFirestore(
            eventId: eventId, userId: hostUserId, existingHostId: hostUserId,
            eventDate: testDate, firestore: self.mockFirestore
        )
        let playStateDocPath = "Public Rooms/\(formattedDateForPath(date: testDate))/Events/\(eventId)/sync/playState"
        let playStateRef = self.mockFirestore.document(playStateDocPath)
        let initialPlayingPosition = 15.0
        try await playStateRef.setData([ // Initial state: Playing at 15s
            "isPlaying": true,
            "playbackPosition": initialPlayingPosition,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": UUID().uuidString
        ], merge: true)

        // 2. Configure service as non-host
        print("🧪 [Test 13] Configuring sync as non-host (\(nonHostUserId))...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: nonHostUserId, event: liveEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed for non-host.")
        try await poll(until: { !self.service.isHost }, timeout: 2.0)
        XCTAssertFalse(service.isHost, "Service should NOT be host.")

        // 3. Setup player and start sync. Player should initially be playing (reflecting Firestore).
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        print("🧪 [Test 13] Starting sync with player for non-host...")
        await service.startSync(with: player)

        try await poll(until: { // Wait for initial sync to playing state
            player.status == .readyToPlay &&
            self.service.isPlayStateListenerActive &&
            player.timeControlStatus == .playing &&
            self.service.isPlayingState == true &&
            abs(player.currentTime().seconds - initialPlayingPosition) < self.service.syncThreshold + 0.5
        }, timeout: 5.0)
        XCTAssertEqual(player.timeControlStatus, .playing, "Player should initially be playing by Firestore state.")
        XCTAssertTrue(service.isPlayingState, "Service should initially be playing.")
        print("🧪 [Test 13] Non-host initially playing. Ready for Firestore PAUSE command.")

        // ACT: Directly write to the playState document in Firestore to simulate host commanding PAUSE
        let pauseCommandUpdateId = UUID().uuidString
        let targetPausePosition = player.currentTime().seconds // Use current player time or a specific one
        print("🧪 [Test 13] Simulating host: Writing PAUSE (false) and position (\(String(format: "%.2f", targetPausePosition))s) to Firestore...")
        try await playStateRef.setData([
            "isPlaying": false,
            "playbackPosition": targetPausePosition,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": pauseCommandUpdateId
        ], merge: true)

        // ASSERT: Service updates local state, player pauses. Position should ideally hold.
        try await poll(until: { // Wait for the listener to react and update player
            self.service.isPlayingState == false &&
            player.timeControlStatus == .paused
        }, timeout: 3.0)

        XCTAssertFalse(service.isPlayingState, "Service's isPlayingState should become false.")
        XCTAssertEqual(player.timeControlStatus, .paused, "Player should pause.")
        // Player's current time might drift slightly after pause, so check with tolerance
        // or assert that it's close to targetPausePosition if that's what the server sent.
        XCTAssertEqual(service.currentTime, targetPausePosition, accuracy: 0.5, "Service currentTime should update to \(targetPausePosition)s.")
        // The player's actual time after pause might be a tiny bit off from the exact server position.
        XCTAssertEqual(player.currentTime().seconds, targetPausePosition, accuracy: 0.5 + self.service.syncThreshold, "Player's time should be around the pause position.")

        print("✅ [Test 13] Completed: Non-host received PAUSE, player paused.")
    }


    @MainActor
    func test14_playStateListener_nonHostReceivesSeekCommand_playerSeeks() async throws {
        // ARRANGE
        let eventId = "nonHostListenerSeekEvent"
        let hostUserId = "theHostForListenerTestC"
        let nonHostUserId = "listenerUserSeek"
        let liveEvent = makeLiveEvent(id: eventId)
        let testDate = service.event?.date ?? Date()

        // 1. Pre-populate Firestore. Player playing at 5s. (Assuming blank.mp4 is > 5s)
        let initialPosition = 5.0
        print("🧪 [Test 14] Setting up initial host and PLAYING state at \(initialPosition)s in Firestore...")
        try await createTestEventInFirestore(
            eventId: eventId, userId: hostUserId, existingHostId: hostUserId,
            eventDate: testDate, firestore: self.mockFirestore
        )
        let playStateDocPath = "Public Rooms/\(formattedDateForPath(date: testDate))/Events/\(eventId)/sync/playState"
        let playStateRef = self.mockFirestore.document(playStateDocPath)
        try await playStateRef.setData([
            "isPlaying": true,
            "playbackPosition": initialPosition,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": UUID().uuidString
        ], merge: true)

        // 2. Configure service as non-host
        print("🧪 [Test 14] Configuring sync as non-host (\(nonHostUserId))...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: nonHostUserId, event: liveEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed for non-host.")
        try await poll(until: { !self.service.isHost }, timeout: 3.0) // Increased timeout slightly

        // 3. Setup player and start sync.
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4")) // Ensure blank.mp4 is long enough
        print("🧪 [Test 14] Starting sync with player for non-host...")
        await service.startSync(with: player)

        // Poll for initial state: playing at initialPosition
        print("🧪 [Test 14] Waiting for initial sync: playing at ~\(initialPosition)s")
        try await poll(until: {
            player.status == .readyToPlay &&
            self.service.isPlayStateListenerActive &&
            player.timeControlStatus == .playing &&
            self.service.isPlayingState == true &&
            abs(player.currentTime().seconds - initialPosition) < (self.service.syncThreshold + 0.5) &&
            abs(self.service.currentTime - initialPosition) < (self.service.syncThreshold + 0.5) // Also check service.currentTime
        }, timeout: 5.0)
        
        let currentTimeAfterInitialSync = await service.currentTime // Read after poll
        print("🧪 [Test 14] Non-host initially playing at \(String(format: "%.2f",player.currentTime().seconds))s (Service time: \(String(format: "%.2f",currentTimeAfterInitialSync))s). Ready for Firestore SEEK command.")
        XCTAssertEqual(player.timeControlStatus, .playing, "Player should be playing after initial sync.")
        XCTAssertTrue(service.isPlayingState, "Service should be playing after initial sync.")
        XCTAssertEqual(currentTimeAfterInitialSync, initialPosition, accuracy: self.service.syncThreshold + 0.5, "Service currentTime should match initial position.")


        // ACT: Directly write to playState in Firestore to simulate host commanding a SEEK
        let seekTargetPosition = 20.0 // Assuming blank.mp4 is now > 20s
        print("🧪 [Test 14] Simulating host: Writing new position (\(seekTargetPosition)s) to Firestore (isPlaying remains true)...")
        try await playStateRef.setData([
            "isPlaying": true,
            "playbackPosition": seekTargetPosition,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": UUID().uuidString
        ], merge: true)

        // ASSERT: Player seeks, isPlaying state remains true, service.currentTime updates.
        print("🧪 [Test 14] Waiting for non-host to seek to ~\(seekTargetPosition)s and remain playing...")
        try await poll(until: {
            self.service.isPlayingState == true &&
            player.timeControlStatus == .playing && // Player should continue playing
            abs(player.currentTime().seconds - seekTargetPosition) < (self.service.syncThreshold + 1.0) && // Increased tolerance for seek settling
            abs(self.service.currentTime - seekTargetPosition) < (self.service.syncThreshold + 0.5) // Crucial: service.currentTime must update
        }, timeout: 5.0)

        let serviceTimeAfterSeek = await service.currentTime // Read after poll
        let playerTimeAfterSeek = player.currentTime().seconds // Read after poll

        XCTAssertTrue(service.isPlayingState, "Service's isPlayingState should remain true after seek.")
        XCTAssertEqual(player.timeControlStatus, .playing, "Player should remain playing after seek.")
        XCTAssertEqual(serviceTimeAfterSeek, seekTargetPosition, accuracy: self.service.syncThreshold + 0.5, "Service currentTime should update to \(seekTargetPosition)s. Was \(serviceTimeAfterSeek)")
        XCTAssertEqual(playerTimeAfterSeek, seekTargetPosition, accuracy: self.service.syncThreshold + 1.0, "Player should seek to \(seekTargetPosition)s. Was \(playerTimeAfterSeek)")

        print("✅ [Test 14] Completed: Non-host received SEEK, player seeked and remained playing.")
    }
    
    @MainActor
    func test15_playStateListener_hostReceivesExternalUpdate_ignoresForControl_updatesLocalStateIfNotEcho() async throws {
        // ARRANGE
        let eventId = "hostReceivesExternalUpdateEvent"
        let hostUserId = "hostUser_Test15"
        let liveEvent = makeLiveEvent(id: eventId) // Ensure this event is "live"
        let testDate = service.event?.date ?? Date()

        // 1. Configure service as host
        print("🧪 [Test 15] Configuring sync as host (\(hostUserId))...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: hostUserId, event: liveEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed for host.")
        try await poll(until: { self.service.isHost }, timeout: 2.0)
        XCTAssertTrue(service.isHost, "Service should be host.")

        // 2. Setup player, start sync, and ensure player is playing at a known state
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        await service.startSync(with: player)

        // Wait for host to start playing (e.g., at 0s, isPlaying: true) and for Firestore to reflect this
        try await poll(until: {
            player.status == .readyToPlay &&
            self.service.isPlayStateListenerActive &&
            player.timeControlStatus == .playing &&
            self.service.isPlayingState == true
        }, timeout: 5.0)
        
        // Let player play for a bit to a known position, e.g., 2 seconds
        // This also ensures the host's time observer has a chance to write its state to Firestore
        try await Task.sleep(for: .seconds(2.5)) // Play for ~2s, allow time observer to fire (0.5s interval, 1.5s debounce)
        
        let expectedPlayerTime = player.currentTime().seconds
        let expectedIsPlayingState = true // Host is actively playing
        print("🧪 [Test 15] Host player is playing at ~\(String(format: "%.2f", expectedPlayerTime))s. Service state: isPlaying=\(service.isPlayingState), currentTime=\(String(format: "%.2f", service.currentTime))s.")


        // ACT: Directly write a *different* playState to Firestore using a new updateId (simulating an external change)
        let externalUpdateId = UUID().uuidString
        let externalPlaybackPosition = 30.0 // A position the local player is not at
        let externalIsPlaying = false      // A different playing state
        
        let playStateRef = try XCTUnwrap(service.getBasePath()?.document("playState"))
        print("🧪 [Test 15] Simulating external update: Writing isPlaying=\(externalIsPlaying), pos=\(externalPlaybackPosition)s, updateId=\(externalUpdateId) to Firestore...")
        try await self.mockFirestore.document(playStateRef.path).setData([
            "isPlaying": externalIsPlaying,
            "playbackPosition": externalPlaybackPosition,
            "updatedAt": FieldValue.serverTimestamp(),
            "updateId": externalUpdateId
        ], merge: true)

        // Give a moment for the listener to fire
        print("🧪 [Test 15] Waiting briefly for host's listener to process external update...")
        try await Task.sleep(for: .milliseconds(500)) // Time for listener to react

        // ASSERT:
        // The host should IGNORE this external update for controlling its own player.
        // Its local player state and its `service.isPlayingState/currentTime` (driven by its player) should NOT change
        // due to this specific listener callback.
        // The host will eventually overwrite this Firestore state with its own true state via its time observer.

        print("🧪 [Test 15] Asserting host's local state remains unchanged by external Firestore write...")
        XCTAssertEqual(service.isPlayingState, expectedIsPlayingState, "Host's service.isPlayingState should NOT change due to external non-echo update.")
        XCTAssertEqual(player.timeControlStatus, .playing, "Host's player should still be playing.")
        XCTAssertEqual(service.currentTime, expectedPlayerTime, accuracy: 1.0, "Host's service.currentTime should be near its original position, not the external one.")
        XCTAssertEqual(player.currentTime().seconds, expectedPlayerTime, accuracy: 1.0, "Host's player currentTime should be near its original position.")

        // Verify that the service's lastFirestorePlayStateUpdateId is NOT the externalUpdateId
        let lastSentId = await service.lastFirestorePlayStateUpdateId // Assuming lastFirestorePlayStateUpdateId is MainActor isolated if accessed directly
        XCTAssertNotEqual(lastSentId, externalUpdateId, "Host should not have adopted the external updateId as its own last sent ID.")

        // Optional: Further wait and check if the host overwrites the Firestore state.
        // This requires waiting for the host's timeObserver's updateFirestorePlayState call.
        print("🧪 [Test 15] Waiting for host to potentially overwrite external state in Firestore...")
        try await Task.sleep(for: .seconds(2.0)) // Wait for time observer + debounce period

        let finalPlayStateSnap = try await self.mockFirestore.document(playStateRef.path).getDocument()
        XCTAssertTrue(finalPlayStateSnap.exists)
        let finalFirestoreIsPlaying = finalPlayStateSnap.data()?["isPlaying"] as? Bool
        let finalFirestoreUpdateId = finalPlayStateSnap.data()?["updateId"] as? String

        XCTAssertEqual(finalFirestoreIsPlaying, expectedIsPlayingState, "Firestore should eventually be overwritten by host's true playing state.")
        XCTAssertNotEqual(finalFirestoreUpdateId, externalUpdateId, "Firestore updateId should be the host's own, not the external one.")
        // The updateId here would be from the host's time observer.

        print("✅ [Test 15] Completed: Host correctly handled external Firestore update.")
    }

    @MainActor
    func test16_playStateListener_updateIsEcho_isIgnored() async throws {
        // ARRANGE
        let eventId = "hostEchoTestEvent"
        let hostUserId = "hostUser_Test16"
        let liveEvent = makeLiveEvent(id: eventId)

        // 1. Configure service as host
        print("🧪 [Test 16] Configuring sync as host (\(hostUserId))...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: hostUserId, event: liveEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed for host.")
        try await poll(until: { self.service.isHost }, timeout: 2.0)

        // 2. Setup player and start sync. Let it get to a playing state.
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        await service.startSync(with: player)
        try await poll(until: { player.timeControlStatus == .playing && self.service.isPlayingState }, timeout: 5.0)
        print("🧪 [Test 16] Host player is playing.")

        // ACT 1: Host performs a local action (e.g., pause) which writes to Firestore.
        print("🧪 [Test 16] Host performing local PAUSE action...")
        await service.handlePlayPause(isPlaying: false) // This uses forceUpdate: true
        
        // Verify local state and player are paused
        try await poll(until: { player.timeControlStatus == .paused && !self.service.isPlayingState }, timeout: 2.0)
        XCTAssertFalse(service.isPlayingState, "Service should be paused after host action.")
        XCTAssertEqual(player.timeControlStatus, .paused, "Player should be paused after host action.")

        // Get the state written to Firestore by the host's action
        let playStateRef = try XCTUnwrap(service.getBasePath()?.document("playState"))
        let snapshotAfterHostAction = try await self.mockFirestore.document(playStateRef.path).getDocument()
        XCTAssertTrue(snapshotAfterHostAction.exists)
        let hostWrittenData = snapshotAfterHostAction.data()
        XCTAssertNotNil(hostWrittenData, "Host should have written data to Firestore.")
        XCTAssertEqual(hostWrittenData?["isPlaying"] as? Bool, false, "Firestore should reflect host's pause action.")
        let hostWrittenUpdateId = hostWrittenData?["updateId"] as? String
        XCTAssertNotNil(hostWrittenUpdateId, "Host write should have an updateId.")
        // Check that the service's internal lastFirestorePlayStateUpdateId matches this
        XCTAssertEqual(service.lastFirestorePlayStateUpdateId, hostWrittenUpdateId, "Service's last sent ID should match what was written.")
        
        print("🧪 [Test 16] Host paused, Firestore updated. Current local player time: \(player.currentTime().seconds)")
        let preEchoPlayerTime = player.currentTime().seconds
        let preEchoIsPlayingState = service.isPlayingState // Should be false

        // ACT 2: Simulate the listener receiving this exact same update (the echo)
        // We do this by re-writing the exact same data to Firestore, which will trigger the listener.
        print("🧪 [Test 16] Simulating echo: Re-writing same data to Firestore path: \(playStateRef.path)...")
        try await self.mockFirestore.document(playStateRef.path).setData(hostWrittenData!) // Write the exact same data back

        // Give a moment for the listener to fire and (hopefully) ignore the echo.
        print("🧪 [Test 16] Waiting briefly for listener to process the echo...")
        try await Task.sleep(for: .milliseconds(500))


        // ASSERT:
        // 1. The "Ignoring Firestore update (echo detected)" log should have appeared (need to check console output for this).
        // 2. The service's state and player's state should NOT have changed *again* due to this echo.
        //    (They are already in the paused state from ACT 1).
        print("🧪 [Test 16] Asserting state after echo...")
        XCTAssertEqual(service.isPlayingState, preEchoIsPlayingState, "isPlayingState should not change due to echo.")
        XCTAssertEqual(player.timeControlStatus, .paused, "Player should remain paused.")
        XCTAssertEqual(player.currentTime().seconds, preEchoPlayerTime, accuracy: 0.1, "Player time should not change due to echo.")
        
        // 3. The service's lastFirestorePlayStateUpdateId should still be the same.
        XCTAssertEqual(service.lastFirestorePlayStateUpdateId, hostWrittenUpdateId, "lastFirestorePlayStateUpdateId should not change due to echo.")

        // To truly confirm the log, you would need a way to intercept logs in tests,
        // or manually check the console output for the "🔄 Ignoring Firestore update (echo detected)" message
        // with the specific updateId. For now, the state check is a good proxy.
        print("✅ [Test 16] Completed. Echo should have been ignored. Manual log check recommended for 'echo detected' message.")
    }
    
    @MainActor
    func test17_hostElection_currentHostLeaves_newHostIsElected() async throws {
        // ARRANGE
        let eventId = "electionEvent_HostLeaves"
        let originalHostId = "userA_OriginalHost"
        let newHostCandidateId = "userB_NewHostCandidate" // This will be our service's userId
        let liveEvent = makeLiveEvent(id: eventId)
        // Use a fixed date for path consistency throughout this test run
        let fixedTestDate = Date() // Or a specific calendar date if your logic depends on it
        let dateString = formattedDateForPath(date: fixedTestDate)

        let syncBasePath = "Public Rooms/\(dateString)/Events/\(eventId)/sync"
        let hostDocRef = self.mockFirestore.document("\(syncBasePath)/host")
        let playStateDocRef = self.mockFirestore.document("\(syncBasePath)/playState")
        let originalHostPresenceRef = self.mockFirestore.document("\(syncBasePath)/presence/activeViewers/\(originalHostId)")
        let newHostCandidatePresenceRef = self.mockFirestore.document("\(syncBasePath)/presence/activeViewers/\(newHostCandidateId)")

        print("🧪 [Test 17] Arranging: Setting up original host (\(originalHostId)) in Firestore...")
        // 1. Set up UserA (originalHostId) as the active host
        try await hostDocRef.setData([
            "hostId": originalHostId,
            "status": "active",
            "timestamp": FieldValue.serverTimestamp(),
            "lastUpdate": FieldValue.serverTimestamp()
        ])
        // 2. Set up UserA's presence (joined earlier)
        try await originalHostPresenceRef.setData([
            "userId": originalHostId,
            "lastSeen": FieldValue.serverTimestamp(),
            "joined": Timestamp(date: fixedTestDate.addingTimeInterval(-120)), // Joined 2 mins ago
            "status": "active",
            "isHost": true
        ])
        // 3. Set up initial playState
        try await playStateDocRef.setData([
            "isPlaying": false, "playbackPosition": 0.0,
            "updatedAt": FieldValue.serverTimestamp(), "updateId": UUID().uuidString
        ])

        // 4. Configure our service instance as UserB (newHostCandidateId)
        // This instance will also need its event.date to match fixedTestDate for getBasePath()
        let eventForNewHost = CalendarEvent(id: liveEvent.id, title: liveEvent.title, date: fixedTestDate, end: liveEvent.end, description: liveEvent.description, color: liveEvent.color, videoURL: liveEvent.videoURL)

        print("🧪 [Test 17] Configuring service as potential new host (\(newHostCandidateId))...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: newHostCandidateId, event: eventForNewHost)
        XCTAssertTrue(configSuccess, "Sync configuration for UserB should succeed.")

        // UserB (service instance) should register its own presence. Poll for its existence.
        // Its 'joined' timestamp will be later than UserA's.
        try await poll19(until: {
            let snap = try await newHostCandidatePresenceRef.getDocument()
            return snap.exists
        }, timeout: 3.0, description: "Waiting for \(newHostCandidateId)'s presence document")
        
        // UserB should initially see UserA as host and not be host itself.
        try await poll19(until: {
            !self.service.isHost && (self.service.activeViewerCount == 2 || self.service.activeViewerCount == 1)
            // activeViewerCount might be 2 initially, then 1 after originalHostPresenceRef is deleted.
        }, timeout: 3.0, description: "\(newHostCandidateId) to confirm non-host status and see viewers")
        XCTAssertFalse(service.isHost, "\(newHostCandidateId) should initially not be the host.")
        
        let initialHostData = try await hostDocRef.getDocument().data()
        print("🧪 [Test 17] Arrange complete. Initial Firestore Host: \(initialHostData?["hostId"] ?? "nil"), Status: \(initialHostData?["status"] ?? "nil"). Service user: \(newHostCandidateId) (isHost: \(service.isHost)).")

        // ACT: Simulate UserA (originalHostId) leaving.
        print("🧪 [Test 17] Act: Simulating \(originalHostId) leaving by deleting presence and marking host doc inactive...")
        
        // Delete UserA's presence first
        try await originalHostPresenceRef.delete()
        print("🧪 [Test 17] Deleted presence for \(originalHostId). Active viewers should now be 1 (only \(newHostCandidateId)).")
        
        // Wait for activeViewerCount in service to reflect UserA's departure (optional, but good for state check)
        try await poll19(until: { self.service.activeViewerCount == 1 }, timeout: 3.0, description: "activeViewerCount to become 1")
        XCTAssertEqual(service.activeViewerCount, 1, "Active viewer count should be 1 after host leaves.")

        // Now, mark the host document as inactive (or hostId="", status="inactive")
        // This is the primary trigger for UserB's hostListener to initiate an election.
        try await hostDocRef.setData([
            // "hostId": originalHostId, // Keep originalHostId or set to ""
            "hostId": "", // More accurately reflects no current host
            "status": "inactive",
            "timestamp": FieldValue.serverTimestamp()
            // lastActive would be stale
        ], merge: true) // merge:true to update existing doc
        print("🧪 [Test 17] Marked host document inactive. \(newHostCandidateId)'s hostListener should trigger election.")
        
        // ASSERT: After a delay, UserB's service should become host, and Firestore's /host doc should update.
        print("🧪 [Test 17] Asserting: Waiting for \(newHostCandidateId) to become host...")
        
        // Poll for service.isHost to become true AND Firestore host document to update
        var finalHostIdInFirestore: String?
        var finalStatusInFirestore: String?

        try await poll19(until: {
            if !self.service.isHost { return false } // Wait for local service state change first

            // Once local state is true, check Firestore
            let currentHostSnap = try await hostDocRef.getDocument(source: .server)
            finalHostIdInFirestore = currentHostSnap.data()?["hostId"] as? String
            finalStatusInFirestore = currentHostSnap.data()?["status"] as? String
            
            print("Polling check: service.isHost=\(self.service.isHost), FS hostId=\(finalHostIdInFirestore ?? "nil"), FS status=\(finalStatusInFirestore ?? "nil")")
            
            return self.service.isHost == true &&
                   finalHostIdInFirestore == newHostCandidateId &&
                   finalStatusInFirestore == "active"
        }, timeout: 7.0, description: "\(newHostCandidateId) to become host and Firestore to update") // Increased timeout for election + listener propagation

        XCTAssertTrue(service.isHost, "\(newHostCandidateId) should have become the host.")
        XCTAssertEqual(finalHostIdInFirestore, newHostCandidateId, "Firestore hostId should be \(newHostCandidateId).")
        XCTAssertEqual(finalStatusInFirestore, "active", "Firestore host status should be active for \(newHostCandidateId).")

        print("✅ [Test 17] Completed: \(newHostCandidateId) successfully elected as new host.")
    }
    
    @MainActor
    func test18_hostElection_noOtherActiveViewers_hostDocumentBecomesInactive() async throws {
        // ARRANGE
        let eventId = "electionEvent_LoneHostLeaves"
        let loneHostId = "loneHostUser"
        let liveEvent = makeLiveEvent(id: eventId)
        let testDate = service.event?.date ?? Date()
        let dateString = formattedDateForPath(date: testDate)
        let syncBasePath = "Public Rooms/\(dateString)/Events/\(eventId)/sync"
        let hostDocRef = self.mockFirestore.document("\(syncBasePath)/host")

        // 1. Configure service as the lone host
        print("🧪 [Test 18] Configuring sync as lone host (\(loneHostId))...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: loneHostId, event: liveEvent)
        XCTAssertTrue(configSuccess, "Sync configuration for lone host should succeed.")
        
        // Service should become host and create its presence and host documents
        try await poll(until: {
            self.service.isHost &&
            self.service.activeViewerCount == 1
        }, timeout: 3.0)
        XCTAssertTrue(service.isHost, "\(loneHostId) should be host.")
        
        // Verify host document was created correctly by the service
        var hostSnap = try await hostDocRef.getDocument(source: .server)
        XCTAssertTrue(hostSnap.exists, "Host document should have been created by the service.")
        XCTAssertEqual(hostSnap.data()?["hostId"] as? String, loneHostId, "HostId in Firestore should be \(loneHostId).")
        XCTAssertEqual(hostSnap.data()?["status"] as? String, "active", "Host status in Firestore should be active.")
        print("🧪 [Test 18] Arrange complete. \(loneHostId) is host. No other viewers.")

        // ACT: Simulate the lone host leaving by calling cleanup on the service instance
        print("🧪 [Test 18] Act: Simulating lone host (\(loneHostId)) leaving via service.cleanup()...")
        await service.cleanup(level: .full)
        // cleanup(level: .full) calls cleanupDatabasePresence, which for a host,
        // should call initiateHostElection(skipSelf: true).
        // Since there are no other users, initiateHostElection should mark the host doc as inactive.

        // ASSERT: Host document in Firestore becomes inactive
        // Add a small delay for the cleanup and election logic to propagate to Firestore
        print("🧪 [Test 18] Asserting: Waiting for host document to become inactive...")
        try await Task.sleep(for: .milliseconds(500)) // Allow time for Firestore updates from cleanup

        hostSnap = try await hostDocRef.getDocument(source: .server)
        XCTAssertTrue(hostSnap.exists, "Host document should still exist (but be inactive).")
        
        let finalHostId = hostSnap.data()?["hostId"] as? String
        let finalStatus = hostSnap.data()?["status"] as? String
        
        // Check for either empty hostId or specific "nobody" ID if you use one
        XCTAssertTrue(finalHostId == nil || finalHostId == "", "Firestore hostId should be empty after lone host leaves. Was: \(finalHostId ?? "nil")")
        XCTAssertEqual(finalStatus, "inactive", "Firestore host status should be inactive. Was: \(finalStatus ?? "nil")")
        
        XCTAssertFalse(service.isHost, "Service's isHost flag should be false after cleanup.")

        print("✅ [Test 18] Completed: Host document correctly marked inactive after lone host left.")
    }
    
    
    @MainActor
    func test19_nonHostCallsElection_doesNotBecomeHostIfValidHostExists() async throws {
        // ARRANGE
        let eventId = "nonHostElectionAttemptEvent"
        let actualHostId = "userA_ActualHost"
        let nonHostChallengerId = "userB_Challenger" // Service instance will be this user
        let liveEvent = makeLiveEvent(id: eventId)
        let testDate = service.event?.date ?? Date()
        let dateString = formattedDateForPath(date: testDate)
        let syncBasePath = "Public Rooms/\(dateString)/Events/\(eventId)/sync"
        let hostDocRef = self.mockFirestore.document("\(syncBasePath)/host")

        // 1. UserA is the active host in Firestore
        print("🧪 [Test 19] Arranging: Setting up \(actualHostId) as active host in Firestore...")
        try await hostDocRef.setData([
            "hostId": actualHostId,
            "status": "active",
            "timestamp": FieldValue.serverTimestamp(),
            "lastUpdate": FieldValue.serverTimestamp()
        ])
        // Create presence for actualHostId so election logic could find them if it ran fully
         try await self.mockFirestore.document("\(syncBasePath)/presence/activeViewers/\(actualHostId)").setData([
            "userId": actualHostId, "joined": Timestamp(date: Date().addingTimeInterval(-120))
        ])


        // 2. Configure our service as UserB (nonHostChallengerId)
        print("🧪 [Test 19] Configuring service as non-host (\(nonHostChallengerId))...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: nonHostChallengerId, event: liveEvent)
        XCTAssertTrue(configSuccess, "Sync configuration for UserB should succeed.")
        try await poll(until: { !self.service.isHost }, timeout: 2.0) // Ensure it's non-host
        XCTAssertFalse(service.isHost, "\(nonHostChallengerId) should not be host.")

        // ACT: Directly call initiateHostElection from UserB's service instance
        // This requires `initiateHostElection` to be at least `internal`
        print("🧪 [Test 19] Act: Non-host (\(nonHostChallengerId)) attempting to initiate host election...")
        await service.MOCK_TEST_initiateHostElection() // Assuming you create a test-only wrapper or make it internal

        // Give some time for the election transaction to attempt and (hopefully) abort
        try await Task.sleep(for: .milliseconds(500))

        // ASSERT
        print("🧪 [Test 19] Asserting: \(actualHostId) remains host...")
        let finalHostSnap = try await hostDocRef.getDocument(source: .server)
        XCTAssertTrue(finalHostSnap.exists)
        XCTAssertEqual(finalHostSnap.data()?["hostId"] as? String, actualHostId, "Actual host (\(actualHostId)) should remain host in Firestore.")
        XCTAssertEqual(finalHostSnap.data()?["status"] as? String, "active", "Host status should remain active.")
        
        XCTAssertFalse(service.isHost, "Challenger (\(nonHostChallengerId)) should NOT have become host.")
        
        print("✅ [Test 19] Completed: Non-host's attempt to call election did not usurp existing host.")
    }
    
    
    // In VideoSyncServiceTests.swift

    // Test 20 (Based on your image)
    func testPresenceListener_viewerCountUpdates() async throws {
        // ARRANGE
        let eventId = "presenceTestEvent"
        let userId1 = "user1_presence"
        let userId2 = "user2_presence"
        let testDate = Date()
        let calendarEvent = CalendarEvent(id: eventId, title: "Presence Test", date: testDate, end: testDate.addingTimeInterval(3600), description: "Testing presence.", color: 1, videoURL: "http://example.com/video.mp4")

        // Configure sync for user1 (service instance)
        let configSuccess = await service.configureSync(eventId: eventId, userId: userId1, event: calendarEvent)
        XCTAssertTrue(configSuccess, "Sync configuration for user1 should succeed.")
        
        // User1 should become host and their presence registered, count should be 1
        try await poll19(until: { self.service.activeViewerCount == 1 && self.service.isHost }, timeout: 3.0, description: "User1 to be host and viewer count to be 1")
        XCTAssertEqual(service.activeViewerCount, 1, "Initial viewer count should be 1 (user1).")

        // ACT 1: Directly add a presence document for userId2 in Firestore
        print("🧪 testPresenceListener: Adding userId2's presence document...")
        let dateString = formattedDateForPath(date: testDate)
        let presencePathUser2 = "Public Rooms/\(dateString)/Events/\(eventId)/sync/presence/activeViewers/\(userId2)"
        try await self.mockFirestore.document(presencePathUser2).setData([
            "userId": userId2,
            "lastSeen": FieldValue.serverTimestamp(),
            "joined": FieldValue.serverTimestamp(),
            "status": "active",
            "isHost": false
        ])

        // ASSERT 1: service.activeViewerCount increments (using polling)
        try await poll19(until: { self.service.activeViewerCount == 2 }, timeout: 3.0, description: "Viewer count to become 2 after userId2 joins")
        XCTAssertEqual(service.activeViewerCount, 2, "Viewer count should increment to 2.")

        // ACT 2: Delete userId2's presence document
        print("🧪 testPresenceListener: Deleting userId2's presence document...")
        try await self.mockFirestore.document(presencePathUser2).delete()

        // ASSERT 2: service.activeViewerCount decrements
        try await poll19(until: { self.service.activeViewerCount == 1 }, timeout: 3.0, description: "Viewer count to become 1 after userId2 leaves")
        XCTAssertEqual(service.activeViewerCount, 1, "Viewer count should decrement to 1.")
    }
    
    
    // In VideoSyncServiceTests.swift

    // Test 21 (Based on your image)
    @MainActor
    func testEventTime_eventEnds_cleanupIsTriggered() async throws {
        // ARRANGE
        let eventId = "eventEndTimeTest"
        let userId = "userEventEnd"
        // Make the event end very quickly
        let eventDuration = 0.2 // seconds
        let startDate = Date().addingTimeInterval(-10) // Started 10 seconds ago
        let verySoonEndDate = startDate.addingTimeInterval(10 + eventDuration) // Ends 0.2s from now effectively

        let expiringEvent = CalendarEvent(id: eventId, title: "Expiring Event", date: startDate, end: verySoonEndDate, description: "This event will end very soon.", color: 1, videoURL: "http://example.com/video.mp4")

        // Configure. `isWithinEventTime` should be true.
        var configSuccess = await service.configureSync(eventId: eventId, userId: userId, event: expiringEvent)
        XCTAssertTrue(configSuccess, "Initial sync configuration should succeed.")
        
        // Explicitly update and check the initial state
        await service.updateEventTimeStatus_TEST_HELPER() // Use test helper for direct call
        XCTAssertTrue(service.isWithinEventTime, "Service should initially be within event time.")
        
        // Store the state of isWithinEventTime *before* the event is expected to end
        let wasWithinTimeInitially = service.isWithinEventTime

        // ACT
        print("🧪 testEventTime: Waiting for event to end (sleeping for \(eventDuration + 0.3) seconds)...")
        try await Task.sleep(for: .seconds(eventDuration + 0.3)) // Wait slightly longer than event duration

        // Now, explicitly call `checkEventTime` via a test helper.
        // This simulates the timer firing *after* the event has ended.
        // `checkEventTime` will call `updateEventTimeStatus` which should change `isWithinEventTime` to false.
        // Then, because `wasWithinTime` (local to `checkEventTime`) was true and `isWithinEventTime` is now false,
        // it should schedule the async cleanup.
        print("🧪 testEventTime: Simulating timer fire by calling checkEventTime_TEST_HELPER()...")
        await service.checkEventTime_TEST_HELPER()

        // ASSERT
        // First, check if the flag correctly updated to false
        XCTAssertFalse(service.isWithinEventTime, "isWithinEventTime should become false after event end time has passed.")

        // Now, poll for the effects of the async cleanup task that checkEventTime should have launched.
        print("🧪 testEventTime: Polling for cleanup completion (eventId to be nil)...")
        try await poll19(until: { await self.service.eventId == nil }, timeout: 5.0, description: "eventId to become nil after cleanup")

        XCTAssertNil(service.eventId, "eventId should be nil after cleanup triggered by event ending.")
        XCTAssertNil(service.userId, "userId should be nil after cleanup.")
        XCTAssertFalse(service.isHost, "isHost should be false after cleanup.")
        XCTAssertEqual(service.activeViewerCount, 0, "activeViewerCount should be 0 after cleanup.")
    }
    
    
    @MainActor // Interacts with player and service state
    func test22Cleanup_full_resetsAllStateAndRemovesListenersAndPresence() async throws {
        // ARRANGE
        let eventId = "cleanupFullTestEvent"
        let userId = "userCleanupFull"
        let testDate = Date()
        let calendarEvent = CalendarEvent(
            id: eventId,
            title: "Full Cleanup Test",
            date: testDate,
            end: testDate.addingTimeInterval(3600),
            description: "Testing full cleanup.",
            color: 1,
            videoURL: "http://example.com/video.mp4"
        )

        // 1. Configure sync and become host
        print("🧪 ARRANGE: Configuring sync for \(userId) in \(eventId)...")
        var configSuccess = await service.configureSync(eventId: eventId, userId: userId, event: calendarEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed.")
        
        // Ensure user becomes host and state is active
        try await poll19(until: { self.service.isHost && self.service.activeViewerCount == 1 }, timeout: 3.0, description: "User to become host with activeViewerCount 1")
        XCTAssertTrue(service.isHost, "User should be host.")
        XCTAssertNotNil(service.event, "Event should be set.")
        XCTAssertEqual(service.eventId, eventId, "Event ID should be set.")
        XCTAssertEqual(service.userId, userId, "User ID should be set.")

        // 2. Start sync with a player
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        await service.startSync(with: player)
        try await poll19(until: { self.service.isPlayStateListenerActive && player.timeControlStatus == .playing }, timeout: 5.0, description: "Player to start playing and playState listener to be active")
        XCTAssertNotNil(service.currentPlayer, "Current player should be set.")
        XCTAssertTrue(service.isPlayStateListenerActive, "PlayState listener should be active.")
        // You can also check if timers are active if you have a way to inspect that (e.g., a test-only property)

        // 3. Verify presence document exists for the user
        let dateString = formattedDateForPath(date: testDate)
        let presencePath = "Public Rooms/\(dateString)/Events/\(eventId)/sync/presence/activeViewers/\(userId)"
        var presenceDoc = try await self.mockFirestore.document(presencePath).getDocument()
        XCTAssertTrue(presenceDoc.exists, "Presence document for user should exist before cleanup.")

        // 4. Verify host document shows this user as host
        let hostPath = "Public Rooms/\(dateString)/Events/\(eventId)/sync/host"
        var hostDoc = try await self.mockFirestore.document(hostPath).getDocument()
        XCTAssertTrue(hostDoc.exists, "Host document should exist.")
        XCTAssertEqual(hostDoc.data()?["hostId"] as? String, userId, "User should be listed as host before cleanup.")

        // ACT
        print("🧪 ACT: Calling service.cleanup(level: .full)...")
        await service.cleanup(level: .full)

        // ASSERT
        print("🧪 ASSERT: Verifying state after full cleanup...")

        // Player is nil/paused (currentPlayer should be nil after full cleanup)
        XCTAssertNil(service.currentPlayer, "currentPlayer should be nil after full cleanup.")
        // Player instance itself would be paused by cleanup before being nilled.

        // Listeners removed (isPlayStateListenerActive is false).
        // The cleanupListeners method sets this flag.
        XCTAssertFalse(service.isPlayStateListenerActive, "isPlayStateListenerActive should be false.")
        // Note: Verifying actual ListenerRegistration.remove() calls is harder without more intricate mocking.
        // Checking `service.listeners.isEmpty` could also be an assertion if `cleanupListeners` clears it.
        // Assuming your cleanupListeners() also empties the `listeners` array:
        // XCTAssertTrue(service.MOCK_getInternalListenersArray().isEmpty, "Internal listeners array should be empty") // Requires test helper

        // Timers invalidated
        // Similar to listeners, verifying timer invalidation often relies on side effects or test helpers.
        // XCTAssertTrue(service.MOCK_getInternalTimersArray().allSatisfy { !$0.isValid }, "All internal timers should be invalidated")

        // eventId, userId, isHost, etc., are reset.
        XCTAssertNil(service.eventId, "eventId should be reset to nil.")
        XCTAssertNil(service.userId, "userId should be reset to nil.")
        XCTAssertNil(service.event, "event object should be reset to nil.")
        XCTAssertFalse(service.isHost, "isHost should be reset to false.")
        XCTAssertFalse(service.isPlayingState, "isPlayingState should be reset to false.")
        XCTAssertEqual(service.currentTime, 0.0, "currentTime should be reset to 0.0.")
        XCTAssertEqual(service.activeViewerCount, 0, "activeViewerCount should be reset to 0.")
        XCTAssertFalse(service.isWithinEventTime, "isWithinEventTime should be false (or reset based on no event).")
        XCTAssertNil(service.lastError, "lastError should be nil (or reset).")
        XCTAssertNil(service.currentSnapshot, "currentSnapshot should be nil.")
        XCTAssertEqual(service.currentViewState, .none, "currentViewState should be .none.")


        // Presence document for the user is deleted from Firestore.
        // cleanup(level: .full) calls cleanupDatabasePresence, which deletes the user's presence doc.
        // It also triggers an election where, since this user (the only one) is gone,
        // the /host doc should become inactive.
        
        // Poll for presence document to be deleted
        try await poll19(until: {
            let doc = try await self.mockFirestore.document(presencePath).getDocument()
            return !doc.exists
        }, timeout: 5.0, description: "Presence document for user to be deleted.")
        
        presenceDoc = try await self.mockFirestore.document(presencePath).getDocument()
        XCTAssertFalse(presenceDoc.exists, "Presence document for user should be deleted after full cleanup.")

        // Verify host document is now inactive (because the only user, who was host, left)
        try await poll19(until: {
            let doc = try await self.mockFirestore.document(hostPath).getDocument()
            return doc.data()?["status"] as? String == "inactive"
        }, timeout: 5.0, description: "Host document to become inactive.")

        hostDoc = try await self.mockFirestore.document(hostPath).getDocument()
        XCTAssertTrue(hostDoc.exists, "Host document should still exist.")
        XCTAssertEqual(hostDoc.data()?["status"] as? String, "inactive", "Host status should be inactive.")
        // hostId might be "" or the original userId depending on how initiateHostElection (with no candidates) behaves
        XCTAssertTrue((hostDoc.data()?["hostId"] as? String == "" || hostDoc.data()?["hostId"] == nil), "HostId should be empty or nil in host document.")
    }
    
    
    // In VideoSyncServiceTests.swift

    @MainActor // Interacts with player and service state
    func test24Cleanup_light_removesObserverKeepsPlayerAndState() async throws {
        // ARRANGE
        let eventId = "cleanupLightEvent"
        let userId = "userCleanupLight"
        let testDate = Date()
        let calendarEvent = CalendarEvent(
            id: eventId,
            title: "Light Cleanup Test",
            date: testDate,
            end: testDate.addingTimeInterval(3600),
            description: "Testing light cleanup.",
            color: 1,
            videoURL: "http://example.com/video.mp4"
        )

        // Define paths for Firestore document verification (though not expected to change)
        let dateString = formattedDateForPath(date: testDate)
        let presencePath = "Public Rooms/\(dateString)/Events/\(eventId)/sync/presence/activeViewers/\(userId)"
        let hostPath = "Public Rooms/\(dateString)/Events/\(eventId)/sync/host"

        // 1. Configure sync and become host
        print("🧪 ARRANGE: Configuring sync for \(userId) in \(eventId)...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: userId, event: calendarEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed.")
        
        try await poll19(until: { self.service.isHost && self.service.activeViewerCount == 1 }, timeout: 3.0, description: "User to become host")
        XCTAssertTrue(service.isHost, "User should be host.")
        
        // Store initial state values
        let initialEventId = service.eventId
        let initialUserId = service.userId
        let initialIsHost = service.isHost
        let initialEvent = service.event
        
        // 2. Start sync with a player, let it play
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        await service.startSync(with: player) // This sets up the time observer
        
        try await poll19(until: {
            self.service.currentPlayer === player && // Player should be set
            player.timeControlStatus == .playing &&
            self.service.isPlayingState &&
            self.service.isPlayStateListenerActive
        }, timeout: 5.0, description: "Player to be set, playing, and listeners active")
        
        let isPlayingStateBeforeCleanup = service.isPlayingState
        let currentTimeBeforeCleanup = service.currentTime
        let playStateListenerActiveBefore = service.isPlayStateListenerActive
        
        // Verify timeObserverToken exists (internal check, ideally)
        // For now, we'll infer its removal by checking that currentTime stops updating IF host.
        // Or, if you add a test helper to check `timeObserverToken == nil`.
        // XCTAssertNotNil(service.MOCK_getTimeObserverToken(), "Time observer token should exist before light cleanup")


        // ACT
        print("🧪 ACT: Calling service.cleanup(level: .light)...")
        await service.cleanup(level: .light)

        // ASSERT
        print("🧪 ASSERT: Verifying state after light cleanup...")

        // Player instance should be RETAINED and its state (e.g. playing) UNCHANGED by .light cleanup itself
        XCTAssertNotNil(service.currentPlayer, "currentPlayer should NOT be nil after light cleanup.")
        XCTAssertTrue(service.currentPlayer === player, "currentPlayer should still be the same player instance.")
        XCTAssertEqual(player.timeControlStatus, .playing, "Player's timeControlStatus should remain playing (light cleanup doesn't pause).")

        // Time observer should be removed.
        // If host, service.currentTime should stop updating automatically from the player.
        // We can test this by letting some physical time pass and ensuring service.currentTime (if host)
        // does NOT advance significantly beyond where it was when the observer was removed.
        // This is a bit indirect. A direct check of `timeObserverToken == nil` via a test helper would be best.
        // For now, let's assume the time was captured around `currentTimeBeforeCleanup`.
        
        let currentTimeAfterCleanupAndDelay = service.currentTime // Read immediately after cleanup
        
        if service.isHost { // Only if host was the time observer actively updating service.currentTime
            try await Task.sleep(for: .seconds(1)) // Wait for some time
            let currentTimeMuchLater = service.currentTime
            // If observer was removed, currentTimeMuchLater should be very close to currentTimeAfterCleanupAndDelay
            XCTAssertEqual(currentTimeMuchLater, currentTimeAfterCleanupAndDelay, accuracy: 0.1, "If host, service.currentTime should not advance after time observer removal by light cleanup.")
        }


        // Core sync state SHOULD be RETAINED:
        XCTAssertEqual(service.eventId, initialEventId, "eventId should be retained.")
        XCTAssertEqual(service.userId, initialUserId, "userId should be retained.")
        XCTAssertEqual(service.isHost, initialIsHost, "isHost status should be retained.")
        XCTAssertNotNil(service.event, "Event object should be retained.")
        XCTAssertEqual(service.event?.id, initialEvent?.id, "Event ID in event object should match.")
        XCTAssertEqual(service.isPlayingState, isPlayingStateBeforeCleanup, "isPlayingState should be retained.")

        // Listeners SHOULD remain active:
        XCTAssertTrue(service.isPlayStateListenerActive, "isPlayStateListenerActive should remain true after light cleanup.")
        // Similar checks for host and presence listeners would involve checking their effects if new data arrived.

        // Timers SHOULD remain active:
        // (Difficult to assert directly without test helpers for timers)

        // Firestore presence and host documents SHOULD NOT be affected:
        let presenceDocAfterCleanup: DocumentSnapshot = try await self.mockFirestore.document(presencePath).getDocument()
        XCTAssertTrue(presenceDocAfterCleanup.exists, "Presence document should still exist after light cleanup.")
        
        let hostDocAfterCleanup: DocumentSnapshot = try await self.mockFirestore.document(hostPath).getDocument()
        XCTAssertTrue(hostDocAfterCleanup.exists, "Host document should still exist.")
        XCTAssertEqual(hostDocAfterCleanup.data()?["hostId"] as? String, userId, "HostId in host document should be unchanged.")
    }
    
    // In VideoSyncServiceTests.swift

    @MainActor
    func test25SwitchToView_storesSnapshot_removesObserver_keepsPlayer() async throws {
        // ARRANGE
        let eventId = "switchViewEvent"
        let userId = "userSwitchView"
        let calendarEvent = makeLiveEvent(id: eventId) // Assuming makeLiveEvent provides a valid event

        _ = await service.configureSync(eventId: eventId, userId: userId, event: calendarEvent)
        try await poll(until: { self.service.isHost }, timeout: 3.0)

        // 1. Switch to initial view and wait for state change
        await service.switchToView(.immersive)
        try await poll19(until: { self.service.currentViewState == .immersive }, timeout: 2.0, description: "Wait for view state to become .immersive")
        XCTAssertEqual(service.currentViewState, .immersive, "Precondition: View state should be .immersive")

        // 2. Start sync with a player
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        await service.startSync(with: player)

        // After switchToView(.immersive)'s async task processes 'player' (set by startSync)
        // and startSync applies the snapshot taken by switchToView,
        // player should be at 0.0 and paused.
        // Then, startSync's host logic will make it play at 0.0.
        try await poll19(until: {
            player.status == .readyToPlay &&
            abs(player.currentTime().seconds - 0.0) < 0.5 &&
            player.timeControlStatus == .playing && // Host logic in startSync should make it play
            self.service.currentSnapshot == nil    // Snapshot from switchToView was applied and cleared
        }, timeout: 5.0, description: "Player to be playing at 0s after startSync and initial switchToView interaction")

        // 3. Manually set player to the desired state for snapshotting (30s, playing)
        let snapshotTargetTime = 30.0
        await player.seek(to: CMTime(seconds: snapshotTargetTime, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        if player.timeControlStatus != .playing { // Ensure it's playing if seek paused it
            player.play()
        }

        try await poll19(until: {
            abs(player.currentTime().seconds - snapshotTargetTime) < 0.5 && player.timeControlStatus == .playing
        }, timeout: 3.0, description: "Player to reach snapshot target (30s, playing)")

        let playerIsPlayingBeforeSwitchToMovieWindow = player.timeControlStatus == .playing
        let playerPositionBeforeSwitchToMovieWindow = player.currentTime().seconds

        // ACT: Switch to .movieWindow. This should snapshot (30s, playing).
        // switchToView will internally call handlePlayPause(false).
        print("🧪 ACT: Calling service.switchToView(.movieWindow)...")
        await service.switchToView(.movieWindow)
        try await poll19(until: { self.service.currentViewState == .movieWindow && self.service.currentSnapshot != nil }, timeout: 2.0, description: "Wait for view state to become .movieWindow and snapshot to be taken")

        // ASSERT
        XCTAssertNotNil(service.currentSnapshot, "Snapshot should be stored.")
        if let snapshot = service.currentSnapshot {
            XCTAssertEqual(snapshot.position, playerPositionBeforeSwitchToMovieWindow, accuracy: 0.5, "Snapshot position should be around 30s.")
            XCTAssertEqual(snapshot.isPlaying, playerIsPlayingBeforeSwitchToMovieWindow, "Snapshot isPlaying should match player state before switch.")
        }

        XCTAssertNil(service.MOCK_getTimeObserverToken(), "Time observer should be removed by switchToView.")
        // The provided code for `switchToView` removes the observer *after* snapshotting.
        // To assert it's removed, you'd check *after* the Task inside `switchToView` completes.
        // For simplicity here, we are checking the snapshot was taken correctly.
        // The line `XCTAssertNil(service.MOCK_getTimeObserverToken(), "Time observer should be removed after switchToView.")` in the original test was premature.
        // A more robust check would be after a delay or a specific completion handler for switchToView's internal task.


        XCTAssertNotNil(service.currentPlayer, "currentPlayer should NOT be nil after switchToView.")
        XCTAssertTrue(service.currentPlayer === player, "currentPlayer should still be the same player instance.")

        // Player should be PAUSED by switchToView's internal handlePlayPause(false)
        try await poll19(until: { player.timeControlStatus == .paused }, timeout: 2.0, description: "Player should be paused by switchToView")
        XCTAssertEqual(player.timeControlStatus, .paused, "Player should be paused by switchToView's handlePlayPause(false).")
        
        XCTAssertEqual(service.currentViewState, .movieWindow, "New view state should be .movieWindow.")
    }
    
    // In VideoSyncServiceTests.swift

    @MainActor
    func testSwitchToView_restoresFromSnapshot_whenReturningToViewWithPlayer() async throws {
        // ARRANGE
        let eventId = "restoreSnapshotEvent"
        let userId = "userRestoreSnapshot"
        let calendarEvent = makeLiveEvent(id: eventId) // Assuming makeLiveEvent is available

        _ = await service.configureSync(eventId: eventId, userId: userId, event: calendarEvent)
        try await poll19(until: { self.service.isHost }, timeout: 3.0, description: "User to become host")

        let initialPlayer = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))

        // 1. Go to initial view and start player
        await service.switchToView(.immersive)
        try await poll(until: { self.service.currentViewState == .immersive }, timeout: 2.0)
        await service.startSync(with: initialPlayer)

        // After switchToView(.immersive)'s async task processing of initialPlayer
        // AND startSync applying the snapshot taken by switchToView (which was likely (0,false)),
        // AND startSync's host logic making it play:
        // initialPlayer should be at 0.0 and PLAYING.
        try await poll19(until: {
            initialPlayer.status == .readyToPlay &&
            abs(initialPlayer.currentTime().seconds - 0.0) < 0.5 &&
            initialPlayer.timeControlStatus == .playing && // Host logic in startSync makes it play
            self.service.currentSnapshot == nil // Snapshot from switchToView applied and cleared
        }, timeout: 5.0, description: "Initial player to be playing at 0s")

        // 2. Set the desired state TO BE SNAPSHOTTED when switching away
        let snapshotPosition = 45.0
        let snapshotIsPlaying = true // We want to snapshot it as playing

        await initialPlayer.seek(to: CMTime(seconds: snapshotPosition, preferredTimescale: 1000))
        if snapshotIsPlaying { initialPlayer.play() } else { initialPlayer.pause() }

        try await poll19(until: {
            abs(initialPlayer.currentTime().seconds - snapshotPosition) < 0.5 &&
            (initialPlayer.timeControlStatus == .playing) == snapshotIsPlaying
        }, timeout: 3.0, description: "Initial player to reach custom state (45s, playing) for snapshotting")

        let intendedSnapshotPosition = initialPlayer.currentTime().seconds
        let intendedSnapshotIsPlaying = initialPlayer.timeControlStatus == .playing

        // 3. Switch to a different view (.movieWindow). This will snapshot (45s, true).
        // switchToView will also call handlePlayPause(false) on initialPlayer.
        print("🧪 ARRANGE: Switching to .movieWindow. Player at \(intendedSnapshotPosition)s, isPlaying: \(intendedSnapshotIsPlaying). This state should be snapshotted.")
        await service.switchToView(.movieWindow)
        try await poll(until: { self.service.currentViewState == .movieWindow && self.service.currentSnapshot != nil }, timeout: 2.0)

        XCTAssertNotNil(service.currentSnapshot, "Snapshot should have been stored by switchToView(.movieWindow).")
        if let storedSnapshot = service.currentSnapshot {
            XCTAssertEqual(storedSnapshot.position, intendedSnapshotPosition, accuracy: 0.5, "Snapshot position should be correct.")
            XCTAssertEqual(storedSnapshot.isPlaying, intendedSnapshotIsPlaying, "Snapshot isPlaying state should be correct.")
        }
        // initialPlayer is now paused at 45s due to switchToView's handlePlayPause(false)
        try await poll(until: { initialPlayer.timeControlStatus == .paused }, timeout: 2.0)


        // Simulate view controller releasing the old player
        service.currentPlayer = nil // Or let startSync handle replacing it. Test needs this to ensure `newImmersivePlayer` becomes current.
        print("🧪 ARRANGE: Simulating old player instance release by setting service.currentPlayer to nil.")

        // 4. Prepare a NEW player instance for the view we are "returning" to.
        let newImmersivePlayer = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))

        // ACT: Switch back to .immersive and start sync with the new player
        print("🧪 ACT: Switching view state back to .immersive...")
        await service.switchToView(.immersive) // This might snapshot newImmersivePlayer (if it were set to currentPlayer) or do nothing to snapshots if currentPlayer is nil
        try await poll(until: { self.service.currentViewState == .immersive }, timeout: 2.0)
        // Crucially, currentSnapshot (45s, true) should still be there from the .movieWindow switch.

        print("🧪 ACT: Immersive view calling startSync with newImmersivePlayer...")
        await service.startSync(with: newImmersivePlayer) // This should apply the (45s, true) snapshot

        // ASSERT: newImmersivePlayer should restore state from the (45s, true) snapshot.
        print("🧪 ASSERT: Polling for newImmersivePlayer to restore snapshot state (pos: \(snapshotPosition)s, isPlaying: \(snapshotIsPlaying))...")
        try await poll19(until: {
            guard newImmersivePlayer.status == .readyToPlay else { return false }
            let positionRestored = abs(newImmersivePlayer.currentTime().seconds - snapshotPosition) < 0.5
            let playStateRestored = (newImmersivePlayer.timeControlStatus == .playing) == snapshotIsPlaying
            return positionRestored && playStateRestored
        }, timeout: 7.0, description: "New player to restore snapshot position and play state.")

        XCTAssertEqual(newImmersivePlayer.currentTime().seconds, snapshotPosition, accuracy: 0.5)
        XCTAssertEqual(newImmersivePlayer.timeControlStatus == .playing, snapshotIsPlaying)
        XCTAssertNil(service.currentSnapshot, "Snapshot should be cleared after being applied.")
        XCTAssertTrue(service.currentPlayer === newImmersivePlayer, "Service's currentPlayer should be newImmersivePlayer.")
    }
    
    
    
    @MainActor // Interacts with player and service state
    func testCleanup_partial_retainsSyncState_cleansPlayer() async throws {
        // ARRANGE
        let eventId = "cleanupPartialEvent"
        let userId = "userCleanupPartial"
        let testDate = Date()
        let calendarEvent = CalendarEvent(
            id: eventId,
            title: "Partial Cleanup Test",
            date: testDate,
            end: testDate.addingTimeInterval(3600),
            description: "Testing partial cleanup.",
            color: 1,
            videoURL: "http://example.com/video.mp4"
        )

        // Define paths for Firestore document verification
        let dateString = formattedDateForPath(date: testDate)
        let presencePath = "Public Rooms/\(dateString)/Events/\(eventId)/sync/presence/activeViewers/\(userId)"
        let hostPath = "Public Rooms/\(dateString)/Events/\(eventId)/sync/host"

        // 1. Configure sync and become host
        print("🧪 ARRANGE: Configuring sync for \(userId) in \(eventId)...")
        let configSuccess = await service.configureSync(eventId: eventId, userId: userId, event: calendarEvent)
        XCTAssertTrue(configSuccess, "Sync configuration should succeed.")

        try await poll19(until: { self.service.isHost && self.service.activeViewerCount == 1 }, timeout: 3.0, description: "User to become host")
        XCTAssertTrue(service.isHost, "User should be host.")

        // Store initial state values to compare later
        let initialEventId = service.eventId
        let initialUserId = service.userId
        let initialIsHost = service.isHost
        let initialEvent = service.event

        // 2. Start sync with a player, let it play, and get some state
        let player = AVPlayer(url: urlInTestBundle(named: "blank", ext: "mp4"))
        await service.startSync(with: player)
        try await poll19(until: {
            self.service.isPlayStateListenerActive &&
            player.timeControlStatus == .playing &&
            self.service.isPlayingState
        }, timeout: 5.0, description: "Player to start playing, playState listener active, service playing state true")

        try await Task.sleep(for: .seconds(1)) // Let player play for a bit
        let timeBeforeCleanup = player.currentTime().seconds
        XCTAssertGreaterThan(timeBeforeCleanup, 0, "Player should have progressed.")
        let isPlayingStateBeforeCleanup = service.isPlayingState
        XCTAssertTrue(isPlayingStateBeforeCleanup, "Service should be in playing state before partial cleanup.")
        let playStateListenerActiveBefore = service.isPlayStateListenerActive
        XCTAssertTrue(playStateListenerActiveBefore, "PlayState listener should be active before partial cleanup.")

        // ACT
        print("🧪 ACT: Calling service.cleanup(level: .partial)...")
        await service.cleanup(level: .partial)

        // ASSERT
        print("🧪 ASSERT: Verifying state after partial cleanup...")

        // Player-related assertions:
        XCTAssertNil(service.currentPlayer, "currentPlayer should be nil after partial cleanup.")

        // Core sync state SHOULD be RETAINED:
        XCTAssertEqual(service.eventId, initialEventId, "eventId should be retained.")
        XCTAssertEqual(service.userId, initialUserId, "userId should be retained.")
        XCTAssertEqual(service.isHost, initialIsHost, "isHost status should be retained.")
        XCTAssertNotNil(service.event, "Event object should be retained.")
        XCTAssertEqual(service.event?.id, initialEvent?.id, "Event ID in event object should match.")

        // isPlayingState and currentTime reflect the state *before* player was nilled by cleanup.
        // The cleanup(level: .partial) pauses the player and nils it, but does not call
        // updateLocalPlayState or updateFirestorePlayState itself.
        // If host, the time observer was updating these; after observer removal, they should hold last values.
        let serviceIsPlayingStateAfterCleanup = service.isPlayingState
        let serviceCurrentTimeAfterCleanup = service.currentTime

        XCTAssertEqual(serviceIsPlayingStateAfterCleanup, isPlayingStateBeforeCleanup, "isPlayingState should be retained (reflecting state before player detachment).")
        XCTAssertEqual(serviceCurrentTimeAfterCleanup, timeBeforeCleanup, accuracy: 0.6, "currentTime should be the last known player time before detachment, with some tolerance.")
        // Increased accuracy slightly for `currentTime` due to potential async nature of player pause vs. time capture.

        // Listeners SHOULD remain active:
        // `isPlayStateListenerActive` is set in `setupVideoSync` and cleared in `cleanupListeners`.
        // `cleanup(level: .partial)` does NOT call `cleanupListeners`.
        XCTAssertTrue(service.isPlayStateListenerActive, "isPlayStateListenerActive should remain true after partial cleanup.")
        // You'd also expect hostListener and presenceListener to still be "active" (i.e., not removed by `cleanupListeners`).

        // Firestore presence and host documents SHOULD NOT be affected by partial cleanup.
        let presenceDocAfterCleanup: DocumentSnapshot = try await self.mockFirestore.document(presencePath).getDocument()
        XCTAssertTrue(presenceDocAfterCleanup.exists, "Presence document should still exist after partial cleanup.")

        let hostDocAfterCleanup: DocumentSnapshot = try await self.mockFirestore.document(hostPath).getDocument()
        XCTAssertTrue(hostDocAfterCleanup.exists, "Host document should still exist.")
        XCTAssertEqual(hostDocAfterCleanup.data()?["hostId"] as? String, userId, "HostId in host document should be unchanged.")
        XCTAssertEqual(hostDocAfterCleanup.data()?["status"] as? String, "active", "Host status in host document should be unchanged.")
    }

    

    // You would need to add this to VideoSyncService.swift for Test 19:
    /*
    #if DEBUG // Or a custom build configuration for testing
    extension VideoSyncService {
        // Test-only wrapper to call the private method
        @MainActor // If initiateHostElection needs it
        func MOCK_TEST_initiateHostElection() async {
            await self.initiateHostElection()
        }
    }
    #endif
    */
    
    
    
    
    
    
    func testConfigureSync_whenNewRoom_initializesAndBecomesHost() async throws {
        // ARRANGE
        let eventId = "testEventNewRoomAlpha"
        let userId = "testUserNewHostAlpha"
        let testDate = Date()

        let calendarEvent = CalendarEvent(
            id: eventId, title: "New Room Test Alpha", date: testDate,
            end: testDate.addingTimeInterval(3600), description: "Testing new room init.",
            color: 1, videoURL: "https://example.com/video_new.mp4"
        )

        // ACT
        print("🧪 testConfigureSync_whenNewRoom: Calling configureSync...")
        let success = await service.configureSync(eventId: eventId, userId: userId, event: calendarEvent)
        print("🧪 testConfigureSync_whenNewRoom: configureSync returned \(success). service.isHost: \(service.isHost)")

        // ASSERT
        XCTAssertTrue(success, "configureSync should return true for a new room setup.")
        if let err = service.lastError { XCTFail("lastError should be nil, but was \(err.localizedDescription)") }
        XCTAssertEqual(service.eventId, eventId)
        XCTAssertEqual(service.userId, userId)
        XCTAssertTrue(service.isWithinEventTime)

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(service.isHost, "User should become the host. service.isHost is \(service.isHost)")

        let dateString = formattedDateForPath(date: testDate)
        let basePath = "Public Rooms/\(dateString)/Events/\(eventId)/sync"

        let hostDocRef = self.mockFirestore.document("\(basePath)/host")
        let hostDoc = try await hostDocRef.getDocument()
        XCTAssertTrue(hostDoc.exists, "Host document should exist. Path: \(hostDocRef.path)")
        XCTAssertEqual(hostDoc.data()?["hostId"] as? String, userId, "HostId mismatch.")
        XCTAssertEqual(hostDoc.data()?["status"] as? String, "active", "Host status mismatch.")

        let playStateDocRef = self.mockFirestore.document("\(basePath)/playState")
        let playStateDoc = try await playStateDocRef.getDocument()
        XCTAssertTrue(playStateDoc.exists, "PlayState document should exist. Path: \(playStateDocRef.path)")
        XCTAssertEqual(playStateDoc.data()?["isPlaying"] as? Bool, false, "isPlaying mismatch.")

        let presenceDocRef = self.mockFirestore.document("\(basePath)/presence/activeViewers/\(userId)")
        let presenceDoc = try await presenceDocRef.getDocument()
        XCTAssertTrue(presenceDoc.exists, "Presence document for user should exist. Path: \(presenceDocRef.path)")
        XCTAssertEqual(presenceDoc.data()?["isHost"] as? Bool, true, "User's presence should mark as host.")

        let expectedCount = 1
        var attempts = 0
        let maxAttempts = 50
        var countMet = false
        print("🧪 Waiting for activeViewerCount to become \(expectedCount)...")
        while !countMet && attempts < maxAttempts {
            if service.activeViewerCount == expectedCount { countMet = true; print("✅ activeViewerCount is \(expectedCount).") }
            else { try await Task.sleep(for: .milliseconds(100)) }
            attempts += 1
        }
        XCTAssertTrue(countMet, "activeViewerCount should become \(expectedCount), but is \(service.activeViewerCount).")
    }

    func testConfigureSync_whenRoomExistsWithOtherHost_userBecomesNonHost() async throws {
        // ARRANGE
        let eventId = "testEventExistingRoomBeta"
        let joiningUserId = "testUserNonHostBeta"
        let existingHostUserId = "testUserOriginalHostBeta"
        let testDate = Date()

        let calendarEvent = CalendarEvent(
            id: eventId, title: "Existing Room Test Beta", date: testDate,
            end: testDate.addingTimeInterval(3600), description: "Joining existing room.",
            color: 2, videoURL: "https://example.com/video_existing.mp4"
        )

        print("🧪 Arranging for existing room: Setting up Firestore data...")
        try await createTestEventInFirestore(
            eventId: eventId, userId: joiningUserId, existingHostId: existingHostUserId,
            eventDate: testDate, firestore: self.mockFirestore
        )
        print("🧪 Arranging for existing room: Firestore data setup complete.")

        // ACT
        print("🧪 Acting: Calling configureSync for existing room...")
        let success = await service.configureSync(eventId: eventId, userId: joiningUserId, event: calendarEvent)
        print("🧪 Acting: configureSync returned \(success). service.isHost: \(service.isHost)")

        // ASSERT
        XCTAssertTrue(success, "configureSync should succeed for an existing room.")
        if let err = service.lastError { XCTFail("lastError should be nil, but was \(err.localizedDescription)") }
        XCTAssertEqual(service.eventId, eventId)
        XCTAssertEqual(service.userId, joiningUserId)

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(service.isHost, "Joining user should NOT become host. service.isHost is \(service.isHost).")

        let dateString = formattedDateForPath(date: testDate)
        let hostDocRef = self.mockFirestore.document("Public Rooms/\(dateString)/Events/\(eventId)/sync/host")
        let hostDoc = try await hostDocRef.getDocument()
        XCTAssertTrue(hostDoc.exists, "Host document should exist.")
        XCTAssertEqual(hostDoc.data()?["hostId"] as? String, existingHostUserId, "HostId should remain original host.")

        let newPresenceDocRef = self.mockFirestore.document("Public Rooms/\(dateString)/Events/\(eventId)/sync/presence/activeViewers/\(joiningUserId)")
        let newPresenceDoc = try await newPresenceDocRef.getDocument()
        XCTAssertTrue(newPresenceDoc.exists, "Presence for joining user should exist.")
        XCTAssertEqual(newPresenceDoc.data()?["isHost"] as? Bool, false, "Joining user's presence should not mark as host.")

        let expectedCount = 2
        var attempts = 0
        let maxAttempts = 50
        var countMet = false
        print("🧪 Waiting for activeViewerCount to become \(expectedCount)...")
        while !countMet && attempts < maxAttempts {
            if service.activeViewerCount == expectedCount { countMet = true; print("✅ activeViewerCount is \(expectedCount).") }
            else { try await Task.sleep(for: .milliseconds(100)) }
            attempts += 1
        }
        XCTAssertTrue(countMet, "activeViewerCount should become \(expectedCount), but is \(service.activeViewerCount).")
    }
}
