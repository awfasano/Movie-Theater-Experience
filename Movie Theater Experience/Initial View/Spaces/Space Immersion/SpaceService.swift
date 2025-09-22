import Foundation
import UIKit
import FirebaseFirestore
import RealityKit
import Combine

class SpaceService: ObservableObject {
    @Published var spaces: [SpaceData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    //@Published var usersInCurrentSpace: [SharePlayUser] = []

    
    static let shared = SpaceService()

    private let db = Firestore.firestore(database: "uploads")
    private var cancellables = Set<AnyCancellable>()
    private var userCountListeners: [String: ListenerRegistration] = [:]
    private var userPresenceRefs: [String: DocumentReference] = [:]
    private var heartbeatTimers: [String: Timer] = [:]
    private var entityCache: [String: Entity] = [:]
    
    private let appModel = AppModel.shared
    
    
    private init() {
        print("SpaceService initialized")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    deinit {
        cleanupAllUserPresence()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Space Fetching
    
    func fetchSpaces() {
        isLoading = true
        errorMessage = nil
        print("Fetching spaces from Firestore...")
        print("Accessing collection: Spaces")
        
        db.collection("Spaces")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Error fetching spaces: \(error.localizedDescription)"
                        print("⚠️ Fetch error: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self.errorMessage = "No documents found"
                        print("⚠️ No documents found in Spaces collection")
                        return
                    }
                    
                    print("📄 Fetched \(documents.count) documents")
                    for doc in documents {
                        print("Document ID: \(doc.documentID)")
                        print("Document data: \(doc.data())")
                    }
                    
                    self.spaces = documents.compactMap { doc in
                        do {
                            let space = try doc.data(as: SpaceData.self)
                            print("✅ Successfully decoded: \(space.spaceName)")
                            return space
                        } catch {
                            print("⚠️ Failed to decode document \(doc.documentID): \(error)")
                            return nil
                        }
                    }
                    
                    print("Total spaces loaded: \(self.spaces.count)")
                    self.setupUserCountObservers()
                }
            }
    }
    
    func fetchUsersInSpace(spaceId: String) async {
        let usersRef = db.collection("Spaces").document(spaceId).collection("activeUsers")
        do {
            let snapshot = try await usersRef.getDocuments()

            // MODIFIED: Get the local user's ID from the AppModel to correctly filter them out.
            let localUserId = await appModel.currentUserId


            await MainActor.run {
                //self.usersInCurrentSpace = users
                //print("Fetched \(users.count) other users in space \(spaceId)")
            }
        } catch {
            print("Error fetching users in space: \(error)")
        }
    }
    
    
    // MARK: - Entity Loading
    
    /// Helper method to extract the child entity named "Root" (if available)
    private func extractRootEntity(from entity: Entity) -> Entity {
        if let rootEntity = entity.findEntity(named: "Root") {
            print("✅ Found root entity: \(rootEntity.name)")
            return rootEntity
        } else {
            print("⚠️ No 'Root' entity found; using loaded entity as root.")
            return entity
        }
    }
    
    // MARK: - Entity Loading

    // Publisher-based version
    func loadSpace(from space: SpaceData) -> AnyPublisher<Entity, Error> {
        return Future<Entity, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(SpaceServiceError.loadingFailed))
                return
            }
            
            if let spaceId = space.id, let cachedEntity = self.entityCache[spaceId] {
                print("✅ Using cached entity for: \(space.spaceName)")
                let clonedEntity = cachedEntity.clone(recursive: true)
                
                // Log Root entity presence but return the complete entity
                if let rootEntity = clonedEntity.findEntity(named: "Root") {
                    print("✅ Found root entity: \(rootEntity.name) inside entity: \(clonedEntity.name)")
                }
                
                // Return the complete entity with its hierarchy intact
                promise(.success(clonedEntity))
                return
            }
            
            guard let url = URL(string: space.usdzURL) else {
                print("⚠️ Invalid URL: \(space.usdzURL)")
                promise(.failure(SpaceServiceError.invalidURL))
                return
            }
            
            print("🔽 Downloading from URL: \(url)")
            
            URLSession.shared.downloadTask(with: url) { [weak self] fileURL, response, error in
                guard let self = self else {
                    promise(.failure(SpaceServiceError.loadingFailed))
                    return
                }
                
                if let error = error {
                    print("⚠️ Download error: \(error)")
                    promise(.failure(error))
                    return
                }
                
                guard let fileURL = fileURL else {
                    print("⚠️ No file URL received")
                    promise(.failure(SpaceServiceError.noData))
                    return
                }
                
                do {
                    let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                    print("📁 File copied to: \(destinationURL)")
                    
                    Task { @MainActor in
                        do {
                            let loadedEntity = try await Entity(contentsOf: destinationURL, withName: nil)
                            
                            // Add name to entity if none exists
                            if await loadedEntity.name.isEmpty {
                                loadedEntity.name = space.spaceName
                            }
                            
                            // Log Root entity presence but return the complete entity
                            if let rootEntity = await loadedEntity.findEntity(named: "Root") {
                                print("✅ Found root entity: \(await rootEntity.name)")
                                
                                // Ensure Root entity is enabled
                                rootEntity.isEnabled = true
                            } else {
                                print("⚠️ No 'Root' entity found in loaded model.")
                            }
                            
                            // Cache and return the complete entity with its hierarchy intact
                            print("✅ Entity loaded successfully with complete hierarchy")
                            
                            if let spaceId = space.id {
                                self.entityCache[spaceId] = await loadedEntity.clone(recursive: true)
                            }
                            
                            promise(.success(loadedEntity))
                        } catch {
                            print("⚠️ Entity loading error: \(error)")
                            promise(.failure(error))
                        }
                    }
                } catch {
                    print("⚠️ File handling error: \(error)")
                    promise(.failure(error))
                }
            }.resume()
        }.eraseToAnyPublisher()
    }

    // Completion handler-based version
    func loadSpace(from space: SpaceData, completion: @escaping (Result<Entity, Error>) -> Void) {
        if let spaceId = space.id, let cachedEntity = entityCache[spaceId] {
            print("✅ Using cached entity for: \(space.spaceName)")
            let clonedEntity = cachedEntity.clone(recursive: true)
            
            // Log Root entity presence but return the complete entity
            if let rootEntity = clonedEntity.findEntity(named: "Root") {
                print("✅ Found root entity: \(rootEntity.name) inside entity: \(clonedEntity.name)")
            }
            
            // Return the complete entity with its hierarchy intact
            completion(.success(clonedEntity))
            return
        }
        
        guard let url = URL(string: space.usdzURL) else {
            completion(.failure(SpaceServiceError.invalidURL))
            return
        }
        
        print("Downloading from URL: \(url)")
        URLSession.shared.downloadTask(with: url) { [weak self] fileURL, response, error in
            guard let self = self else {
                completion(.failure(SpaceServiceError.loadingFailed))
                return
            }
            
            if let error = error {
                print("Download error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let fileURL = fileURL else {
                print("No file URL received")
                completion(.failure(SpaceServiceError.noData))
                return
            }
            
            do {
                let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
                try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                
                Task { @MainActor in
                    do {
                        let loadedEntity = try await Entity(contentsOf: destinationURL, withName: nil)
                        
                        // Add name to entity if none exists
                        if loadedEntity.name.isEmpty {
                            loadedEntity.name = space.spaceName
                        }
                        
                        // Log Root entity existence but return the complete entity
                        if let rootEntity = loadedEntity.findEntity(named: "Root") {
                            print("✅ Found root entity: \(rootEntity.name)")
                            
                            // Ensure Root entity is enabled
                            rootEntity.isEnabled = true
                            
                            // Add a tag to help find it in SpacesView
                            loadedEntity.name = space.spaceName + "_WithRoot"
                        } else {
                            print("⚠️ No 'Root' entity found in loaded model.")
                        }
                        
                        print("✅ Entity loaded successfully with complete hierarchy")
                        
                        if let spaceId = space.id {
                            self.entityCache[spaceId] = loadedEntity.clone(recursive: true)
                        }
                        
                        completion(.success(loadedEntity))
                    } catch {
                        print("Entity loading error: \(error)")
                        completion(.failure(error))
                    }
                }
            } catch {
                print("File handling error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }

    // Helper method to find the Root entity (keep this for debugging)
    func findRootEntity(in entity: Entity) -> Entity? {
        if entity.name == "Root" {
            return entity
        }
        
        return entity.findEntity(named: "Root")
    }
    // MARK: - User Count Management
    
    private func setupUserCountObservers() {
        for listener in userCountListeners.values {
            listener.remove()
        }
        userCountListeners.removeAll()
        
        for space in spaces {
            guard let spaceId = space.id else { continue }
            
            let listener = db.collection("Spaces").document(spaceId)
                .addSnapshotListener { [weak self] document, error in
                    guard let self = self,
                          let document = document,
                          error == nil else {
                        print("Error listening for user count: \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    
                    if let currentCount = document.data()?["currentUserCount"] as? Int,
                       let maxCount = document.data()?["maxUserCount"] as? Int,
                       let index = self.spaces.firstIndex(where: { $0.id == spaceId }) {
                        
                        DispatchQueue.main.async {
                            self.spaces[index].currentUserCount = currentCount
                            self.spaces[index].maxUserCount = maxCount
                        }
                    }
                }
            
            userCountListeners[spaceId] = listener
        }
    }
    
    // In SpaceService.swift

    func joinSpace(_ spaceId: String) async -> Bool {
        // 1. Is the function even being called?
        print("➡️ [Debug] 1. joinSpace called with spaceId: \(spaceId)")

        let user = await appModel.currentUser
        
        // 2. Is the user identity valid in the AppModel?
        print("➡️ [Debug] 2. Checking user: ID = '\(user.id)', Name = '\(user.name)'")

        guard !user.name.isEmpty else {
            print("❌ EXIT: Username is empty.")
            return false
        }
        
        guard !user.id.isEmpty else {
            print("❌ EXIT: UserID is empty.")
            return false
        }
        
        print("✅ [Debug] User identity is valid. Proceeding to database write.")
        
        do {
            let spaceRef = db.collection("Spaces").document(spaceId)
            
            // 3. Trying the first database write...
            print("➡️ [Debug] 3. Attempting to increment currentUserCount...")
            try await spaceRef.updateData(["currentUserCount": FieldValue.increment(Int64(1))])
            print("✅ [Debug] Successfully incremented currentUserCount.")
            
            let userRef = spaceRef.collection("activeUsers").document(user.id)
            
            // 4. Trying the second database write...
            print("➡️ [Debug] 4. Attempting to set data for active user...")
            try await userRef.setData([
                "userId": user.id,
                "userName": user.name,
                "joinedAt": FieldValue.serverTimestamp(),
                "lastUpdate": FieldValue.serverTimestamp() // Add this line
            ])
            print("✅ [Debug] Successfully set data for active user.")
            
            userPresenceRefs[spaceId] = userRef
            startHeartbeat(for: spaceId)
            print("✅ Successfully joined space: \(spaceId) as user: \(user.name) (\(user.id))")
            return true
        } catch {
            // 5. If we land here, a database error occurred.
            print("❌ DATABASE ERROR: Failed to join space: \(error.localizedDescription)")
            return false
        }
    }
    
    func leaveSpace(_ spaceId: String) async {
        // MODIFIED: Get the correct userId from the AppModel to ensure we remove the right document.
        let userId = await appModel.currentUserId
        guard !userId.isEmpty else { return }
        
        // Use the specific user's ref to leave, rather than a potentially incorrect cached one.
        let userRef = db.collection("Spaces").document(spaceId).collection("activeUsers").document(userId)
        
        do {
            let spaceRef = db.collection("Spaces").document(spaceId)
            // Use a transaction to safely decrement the count
            try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                let spaceDocument: DocumentSnapshot
                do {
                    try spaceDocument = transaction.getDocument(spaceRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                guard let oldCount = spaceDocument.data()?["currentUserCount"] as? Int else {
                    let error = NSError(domain: "AppErrorDomain", code: -1, userInfo: [ NSLocalizedDescriptionKey: "Unable to retrieve user count from snapshot." ])
                    errorPointer?.pointee = error
                    return nil
                }
                
                // Decrement count only if it's greater than 0
                transaction.updateData(["currentUserCount": FieldValue.increment(Int64(oldCount > 0 ? -1 : 0))], forDocument: spaceRef)
                return nil
            })

            try await userRef.delete()
            stopHeartbeat(for: spaceId)
            userPresenceRefs.removeValue(forKey: spaceId)
            print("✅ Successfully left space: \(spaceId)")
        } catch {
            print("❌ Failed to leave space: \(error.localizedDescription)")
        }
    }
    
    
    func getCachedEntity(for spaceId: String) -> Entity? {
        return entityCache[spaceId]
    }
    
    func cacheEntity(_ entity: Entity, for spaceId: String) {
        entityCache[spaceId] = entity.clone(recursive: true)
    }
    
    func getSpaceUpdates(for spaceId: String) -> AnyPublisher<SpaceData, Error> {
        return Future<SpaceData, Error> { promise in
            let listener = self.db.collection("Spaces").document(spaceId)
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }
                    
                    guard let document = snapshot, document.exists else {
                        promise(.failure(SpaceServiceError.noData))
                        return
                    }
                    
                    do {
                        var space = try document.data(as: SpaceData.self)
                        if space.id == nil {
                            space.id = document.documentID
                        }
                        promise(.success(space))
                    } catch {
                        promise(.failure(error))
                    }
                }
            
            self.cancellables.insert(AnyCancellable {
                listener.remove()
            })
        }
        .handleEvents(receiveCancel: {
            print("Space updates listener cancelled for space: \(spaceId)")
        })
        .share()
        .eraseToAnyPublisher()
    }
    
    private func startHeartbeat(for spaceId: String) {
        stopHeartbeat(for: spaceId)
        
        let timer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            guard let userRef = self?.userPresenceRefs[spaceId] else { return }
            userRef.updateData([
                "lastUpdate": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("❌ Failed to update heartbeat: \(error.localizedDescription)")
                }
            }
        }
        heartbeatTimers[spaceId] = timer
    }
    
    private func stopHeartbeat(for spaceId: String) {
        heartbeatTimers[spaceId]?.invalidate()
        heartbeatTimers.removeValue(forKey: spaceId)
    }
    
    private func cleanupAllUserPresence() {
        for timer in heartbeatTimers.values {
            timer.invalidate()
        }
        heartbeatTimers.removeAll()
        
        for listener in userCountListeners.values {
            listener.remove()
        }
        userCountListeners.removeAll()
        
        for (spaceId, userRef) in userPresenceRefs {
            let spaceRef = db.collection("Spaces").document(spaceId)
            spaceRef.updateData([
                "currentUserCount": FieldValue.increment(Int64(-1))
            ])
            userRef.delete()
        }
        userPresenceRefs.removeAll()
    }
    
    @objc private func handleAppTermination() {
        cleanupAllUserPresence()
    }
}

enum SpaceServiceError: Error {
    case invalidURL
    case noData
    case loadingFailed
}

extension SpaceServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for USDZ file"
        case .noData:
            return "No data received from server"
        case .loadingFailed:
            return "Failed to load 3D content"
        }
    }
}
