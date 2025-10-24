//
//  TriviaImmersiveManager.swift
//  Movie Theater Experience
//
//  Manages the immersive trivia experience and listens to Firebase triggers
//

import RealityKit
import RealityKitContent
import SwiftUI
import FirebaseFirestore
import Combine
import simd

@MainActor
class TriviaImmersiveManager: ObservableObject {

    @Published private(set) var isImmersiveActive = false
    @Published private(set) var currentTableNumber: Int?

    private var entitySystem: TriviaEntitySystem?
    private var rootEntity: Entity?

    private var broadcastListener: ListenerRegistration?
    private var eventId: String?

    private let db = Firestore.firestore(database: "uploads")

    // MARK: - Setup

    /// Sets up the trivia immersive experience
    func setupImmersiveExperience(for event: CalendarEvent, tableNumber: Int?) async -> Entity {
        print("🎬 [TriviaImmersive] Setting up immersive experience")

        self.eventId = event.id
        self.currentTableNumber = tableNumber

        let system = TriviaEntitySystem()
        let expectedTables = event.tableConfiguration?.maxTables
        let seatsPerTable = event.tableConfiguration?.maxSeatsPerTable ?? 4
        let root: Entity

        if let spaceId = event.spaceId,
           let storedScene = await loadSceneFromStorage(spaceId: spaceId, using: system, expectedTableCount: expectedTables, seatsPerTable: seatsPerTable) {
            root = storedScene
        } else if let storedScene = await loadStoredScene(using: system, expectedTableCount: expectedTables, seatsPerTable: seatsPerTable) {
            root = storedScene
        } else {
            print("⚠️ [TriviaImmersive] Falling back to procedural trivia layout")
            root = system.setupTriviaEntities(
                numberOfTables: expectedTables ?? 6,
                seatsPerTable: seatsPerTable
            )
        }

        self.entitySystem = system
        self.rootEntity = root
        self.isImmersiveActive = true

        // Start listening to Firebase broadcasts for animations
        if let eventId = event.id {
            startBroadcastListener(eventId: eventId)
        }

        return root
    }

    /// Tears down the immersive experience
    func teardownImmersiveExperience() {
        print("🎬 [TriviaImmersive] Tearing down immersive experience")

        broadcastListener?.remove()
        broadcastListener = nil

        rootEntity?.removeFromParent()
        rootEntity = nil
        entitySystem = nil
        isImmersiveActive = false
    }

    // MARK: - FaceTime Participant Management

    /// Adds a FaceTime participant entity to the scene around their table
    func addParticipantEntity(
        tableNumber: Int,
        participantId: String,
        participantEntity: Entity,
        position: Int
    ) {
        entitySystem?.addFaceTimeParticipant(
            to: tableNumber,
            participantId: participantId,
            participantEntity: participantEntity,
            position: position
        )
    }

    /// Removes a participant entity when they leave
    func removeParticipantEntity(tableNumber: Int, participantId: String) {
        entitySystem?.removeFaceTimeParticipant(from: tableNumber, participantId: participantId)
    }

    // MARK: - Firebase Broadcast Listener

    private func startBroadcastListener(eventId: String) {
        print("👂 [TriviaImmersive] Starting broadcast listener for event: \(eventId)")

        broadcastListener = db.collection("Events")
            .document(eventId)
            .collection("broadcasts")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("❌ [TriviaImmersive] Broadcast listener error: \(error)")
                    return
                }

                guard let snapshot = snapshot else { return }

                // Process new broadcasts
                snapshot.documentChanges.forEach { change in
                    if change.type == .added {
                        if let data = try? change.document.data(),
                           let message = data["message"] as? String {
                            Task { @MainActor in
                                self.handleBroadcastMessage(message)
                            }
                        }
                    }
                }
            }
    }

    private func handleBroadcastMessage(_ message: String) {
        print("📢 [TriviaImmersive] Received broadcast: \(message)")

        // Parse messages like "table_1_celebrate" or "table_3_correct_answer"
        let components = message.split(separator: "_")

        if components.count >= 3,
           components[0] == "table",
           let tableNumber = Int(components[1]) {

            // Reconstruct animation name (could be "correct_answer" with underscore)
            let animationName = components[2...].joined(separator: "_")

            if let animation = TableAnimationType(rawValue: animationName) {
                print("🎯 [TriviaImmersive] Triggering \(animationName) on table \(tableNumber)")
                entitySystem?.triggerAnimation(on: tableNumber, animation: animation)
            } else {
                print("⚠️ [TriviaImmersive] Unknown animation: \(animationName)")
            }
        } else {
            print("⚠️ [TriviaImmersive] Unhandled broadcast message: \(message)")
        }
    }

    // MARK: - Manual Animation Triggers (for testing)

    /// Manually trigger an animation (useful for testing without Firebase)
    func triggerAnimationManually(tableNumber: Int, animation: TableAnimationType) {
        print("🎯 [TriviaImmersive] Manually triggering \(animation.rawValue) on table \(tableNumber)")
        entitySystem?.triggerAnimation(on: tableNumber, animation: animation)
    }

    // MARK: - Entity Access

    func getTableEntity(tableNumber: Int) -> Entity? {
        return entitySystem?.getTableEntity(tableNumber: tableNumber)
    }

    func getHostEntity() -> Entity? {
        return entitySystem?.getHostEntity()
    }

    func tablePositions() -> [Int: SIMD3<Float>] {
        entitySystem?.tableWorldPositions() ?? [:]
    }

    func seatPositions(for tableNumber: Int) -> [SIMD3<Float>] {
        entitySystem?.seatWorldPositions(for: tableNumber) ?? []
    }

    func seatPosition(for tableNumber: Int, seatIndex: Int) -> SIMD3<Float>? {
        entitySystem?.seatWorldPosition(for: tableNumber, seatIndex: seatIndex)
    }

    // MARK: - Asset Loading

    private func loadSceneFromStorage(spaceId: String, using system: TriviaEntitySystem, expectedTableCount: Int?, seatsPerTable: Int) async -> Entity? {
        do {
            let snapshot = try await db.collection("Spaces").document(spaceId).getDocument()
            guard snapshot.exists else {
                print("⚠️ [TriviaImmersive] Space document not found for id: \(spaceId)")
                return nil
            }

            let spaceData = try snapshot.data(as: SpaceData.self)
            guard let url = URL(string: spaceData.usdzURL) else {
                print("⚠️ [TriviaImmersive] Invalid USDZ URL for space: \(spaceId)")
                return nil
            }

            let (temporaryURL, _) = try await URLSession.shared.download(from: url)
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("trivia-space-\(spaceId)-\(UUID().uuidString).usdz")

            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: temporaryURL, to: destinationURL)

            let entityTask = Task.detached(priority: .userInitiated) { () throws -> Entity in
                try await Entity.load(contentsOf: destinationURL)
            }
            let entity = try await entityTask.value

            if entity.name.isEmpty {
                entity.name = "TriviaRoot"
            }

            await MainActor.run {
                system.prepareScene(using: entity, expectedTableCount: expectedTableCount, defaultSeatsPerTable: seatsPerTable)
            }

            print("✅ [TriviaImmersive] Loaded immersive scene from storage for spaceId: \(spaceId)")
            return entity
        } catch {
            print("❌ [TriviaImmersive] Failed to load immersive scene for spaceId \(spaceId): \(error)")
            return nil
        }
    }

    private func loadStoredScene(using system: TriviaEntitySystem, expectedTableCount: Int?, seatsPerTable: Int) async -> Entity? {
        let candidateNames = [
            "TriviaSpace",
            "MovieTheatre1",
            "Movie",
            "Immersive Scene",
            "Immersive"
        ]

        for name in candidateNames {
            if let entity = try? await (
                Task.detached(priority: .userInitiated) { () throws -> Entity in
                    try await Entity(named: name, in: realityKitContentBundle)
                }
            ).value {
                await MainActor.run {
                    system.prepareScene(using: entity, expectedTableCount: expectedTableCount, defaultSeatsPerTable: seatsPerTable)
                }
                print("✅ [TriviaImmersive] Using bundled scene: \(name)")
                return entity
            }
        }

        // Attempt to load from packaged USDZ in the main bundle if available.
        let fallbackFileNames = [
            "Movie Theatre Experience/intro",
            "Movie Theatre One",
            "Scene"
        ]

        for name in fallbackFileNames {
            let components = name.split(separator: "/")
            let fileName = components.last.map(String.init) ?? name
            if let url = Bundle.main.url(forResource: fileName, withExtension: "usdz") {
                if let entity = try? await (
                    Task.detached(priority: .userInitiated) { () throws -> Entity in
                        try await Entity.load(contentsOf: url)
                    }
                ).value {
                    await MainActor.run {
                        system.prepareScene(using: entity, expectedTableCount: expectedTableCount, defaultSeatsPerTable: seatsPerTable)
                    }
                    print("✅ [TriviaImmersive] Loaded USDZ from bundle: \(fileName)")
                    return entity
                }
            }
        }

        print("⚠️ [TriviaImmersive] Unable to locate a stored immersive scene asset.")
        return nil
    }
}
