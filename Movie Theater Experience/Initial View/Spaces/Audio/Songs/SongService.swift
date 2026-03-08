
// In SongService.swift

import Foundation
import FirebaseFirestore

final class SongService {
    private let db = Firestore.firestore(database: "uploads")
    
    func fetchSongs(for spaceName: String) async -> [Song] {
        // special-case fix for the trailing-space document
        let docID: String = {
            let lower = spaceName.lowercased()
            if lower == "synthwave" {
                return "synthwave "    // the actual doc ID in Firestore
            }
            return lower
        }()
        
        print("⏳ Fetching songs for space '\(spaceName)' (using docID: '\(docID)')…")
        do {
            let snapshot = try await db.collection("Spaces")
                .document(docID)
                .collection("music")
                .getDocuments()
            
            let fetchedSongs = snapshot.documents.compactMap { try? $0.data(as: Song.self) }
            print("✅ Loaded \(fetchedSongs.count) songs for space '\(spaceName)'")
            return fetchedSongs
        } catch {
            print("❌ Failed to fetch songs for space '\(spaceName)':", error)
            return []
        }
    }
}

