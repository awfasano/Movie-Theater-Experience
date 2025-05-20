//
//  FirebaseStoryService.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 6/21/25.
//

import Foundation
import FirebaseFirestore

/// A service to fetch story data from the Firestore database.
@MainActor
class FirebaseStoryService: ObservableObject {
    @Published var stories: [Story] = []
    private let db = Firestore.firestore(database: "uploads")

    /// Fetches all stories from the 'stories' sub-collection for a given space.
    /// - Parameter spaceId: The document ID of the space (e.g., "space bar").
    func fetchStories(fromSpaceId spaceId: String) {
        let storiesCollection = db.collection("Spaces").document(spaceId).collection("stories")
        
        storiesCollection.getDocuments { (querySnapshot, error) in
            if let error = error {
                print("Error getting stories: \(error.localizedDescription)")
                return
            }

            guard let documents = querySnapshot?.documents else {
                print("No stories found.")
                return
            }

            // Decode each document into a Story object.
            self.stories = documents.compactMap { document in
                do {
                    return try document.data(as: Story.self)
                } catch {
                    print("Error decoding story: \(error)")
                    return nil
                }
            }
        }
    }
}
