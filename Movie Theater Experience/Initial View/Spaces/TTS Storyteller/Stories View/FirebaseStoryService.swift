import Foundation
import FirebaseFirestore
import Combine

/// A service to fetch story data from the Firestore database with optimizations
@MainActor
class FirebaseStoryService: ObservableObject {
    @Published private(set) var stories: [Story] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private let db = Firestore.firestore(database: "uploads")
    private var fetchTask: Task<Void, Never>?

    // Cache management
    private var lastFetchTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    private var cachedSpaceId: String?

    deinit {
        fetchTask?.cancel()
    }

    /// Fetches all stories from the 'stories' sub-collection for a given space
    /// - Parameter spaceId: The document ID of the space (e.g., "space bar")
    func fetchStories(fromSpaceId spaceId: String) async {
        // Check cache validity
        if let lastFetch = lastFetchTime,
           cachedSpaceId == spaceId,
           Date().timeIntervalSince(lastFetch) < cacheValidityDuration,
           !stories.isEmpty {
            print("Using cached stories")
            return
        }

        // Cancel any existing fetch
        fetchTask?.cancel()

        isLoading = true
        error = nil

        // The Task wrapper is removed. The work now runs directly on the MainActor.
        do {
            // Add a small delay to prevent UI flashing on fast connections
            if stories.isEmpty {
                try? await Task.sleep(for: .milliseconds(350))
            }
            
            // Fetch documents
            let storiesCollection = db.collection("Spaces").document(spaceId).collection("stories")
            let querySnapshot = try await storiesCollection.getDocuments()
            
            // Decode documents
            var newStories: [Story] = []
            newStories.reserveCapacity(querySnapshot.documents.count)

            for document in querySnapshot.documents {
                do {
                    let story = try document.data(as: Story.self)
                    newStories.append(story)
                    print(story)
                } catch {
                    print("Error decoding story with ID \(document.documentID): \(error)")
                }
            }
            
            // Update state. This is now guaranteed to be on the main thread.
            self.stories = newStories
            self.lastFetchTime = Date()
            self.cachedSpaceId = spaceId
            self.isLoading = false
            
        } catch {
            print("Error getting stories: \(error.localizedDescription)")
            self.error = error
            self.isLoading = false
        }
    }

    /// Clears the cache and forces a refresh on next fetch
    func clearCache() {
        lastFetchTime = nil
        cachedSpaceId = nil
    }

    /// Cancels any ongoing fetch operation
    func cancelFetch() {
        fetchTask?.cancel()
        isLoading = false
    }
}
