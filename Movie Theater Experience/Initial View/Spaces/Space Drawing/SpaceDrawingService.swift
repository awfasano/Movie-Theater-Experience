//
//  SpaceDrawingService.swift
//  Movie Theater Experience
//
//  Created by GPT-5 Codex on 3/16/25.
//

import Foundation
import FirebaseFirestore
import FirebaseFirestore
import Combine

@MainActor
final class SpaceDrawingService: ObservableObject {
    static let shared = SpaceDrawingService()
    
    @Published private(set) var strokes: [SpaceStroke] = []
    
    private var db: Firestore { Firestore.firestore(database: "uploads") }
    private var listener: ListenerRegistration?
    private var strokesById: [String: SpaceStroke] = [:]
    private var currentSpaceId: String?
    private var pruneTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Listener Management
    
    func start(for spaceId: String) {
        guard spaceId != currentSpaceId else { return }
        stop()
        currentSpaceId = spaceId
        
        listener = collection(for: spaceId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("❌ SpaceDrawingService listener error: \(error)")
                    return
                }
                
                guard let snapshot else { return }
                
                Task { @MainActor in
                    snapshot.documentChanges.forEach { change in
                        self.handle(change: change)
                    }
                }
            }
    }
    
    func stop() {
        listener?.remove()
        listener = nil
        pruneTask?.cancel()
        pruneTask = nil
        currentSpaceId = nil
        strokesById.removeAll()
        strokes.removeAll()
    }
    
    // MARK: - Stroke Operations
    
    func submit(stroke: SpaceStroke) async throws {
        guard let spaceId = currentSpaceId else {
            throw DrawingServiceError.spaceNotConfigured
        }
        guard stroke.spaceId == spaceId else {
            throw DrawingServiceError.invalidSpaceContext
        }
        
        let documentId = stroke.strokeId
        try collection(for: spaceId)
            .document(documentId)
            .setData(from: stroke, merge: false)
        
        schedulePruneIfNeeded()
    }
    
    func deleteStroke(withId strokeId: String) async throws {
        guard let spaceId = currentSpaceId else {
            throw DrawingServiceError.spaceNotConfigured
        }
        try await collection(for: spaceId)
            .document(strokeId)
            .delete()
    }
    
    func clearAll() async throws {
        guard let spaceId = currentSpaceId else {
            throw DrawingServiceError.spaceNotConfigured
        }
        
        let snapshot = try await collection(for: spaceId).getDocuments()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for doc in snapshot.documents {
                let id = doc.documentID
                group.addTask {
                    try await self.collection(for: spaceId).document(id).delete()
                }
            }
            try await group.waitForAll()
        }
    }
    
    // MARK: - Internal Helpers
    
    private func handle(change: DocumentChange) {
        guard var stroke = try? change.document.data(as: SpaceStroke.self) else {
            print("⚠️ Unable to decode stroke document \(change.document.documentID)")
            return
        }
        
        if stroke.strokeId.isEmpty {
            stroke.strokeId = change.document.documentID
        }
        stroke.id = change.document.documentID
        
        switch change.type {
        case .added, .modified:
            strokesById[stroke.strokeId] = stroke
        case .removed:
            strokesById.removeValue(forKey: stroke.strokeId)
        }
        
        refreshPublishedStrokes()
    }
    
    private func refreshPublishedStrokes() {
        let active = strokesById.values
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt < $1.createdAt }
        strokes = active
        schedulePruneIfNeeded()
    }
    
    private func schedulePruneIfNeeded() {
        guard let spaceId = currentSpaceId else { return }
        let totalPoints = strokes.reduce(0) { $0 + $1.points.count }
        guard totalPoints > SpaceDrawingConstants.maxPointCount else { return }
        
        pruneTask?.cancel()
        let strokesToConsider = strokes
        let pointsOverBudget = totalPoints - SpaceDrawingConstants.maxPointCount
        
        pruneTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.prune(oldestStrokes: strokesToConsider, removingAtLeast: pointsOverBudget, in: spaceId)
        }
    }
    
    @MainActor
    private func prune(oldestStrokes: [SpaceStroke], removingAtLeast targetPoints: Int, in spaceId: String) async {
        guard targetPoints > 0 else { return }
        
        var remainingPoints = targetPoints
        for stroke in oldestStrokes.sorted(by: { $0.createdAt < $1.createdAt }) {
            if Task.isCancelled { break }
            do {
                try await collection(for: spaceId)
                    .document(stroke.strokeId)
                    .delete()
                remainingPoints -= stroke.points.count
                if remainingPoints <= 0 {
                    break
                }
            } catch {
                print("⚠️ Failed to prune stroke \(stroke.strokeId): \(error)")
            }
        }
    }
    
    private func collection(for spaceId: String) -> CollectionReference {
        db.collection("Spaces")
            .document(spaceId)
            .collection(SpaceDrawingConstants.collectionName)
    }
    
    enum DrawingServiceError: Error {
        case spaceNotConfigured
        case invalidSpaceContext
    }
}
