import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import RealityKit
import Combine

class SpaceService: ObservableObject {
    @Published var spaces: [SpaceData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore(database: "uploads")
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("SpaceService initialized")
    }
    
    func fetchSpaces() {
        isLoading = true
        errorMessage = nil
        print("Fetching spaces from Firestore...")
        
        // Print the path to help debug
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
                    
                    // Debug: Print raw document data
                    for doc in documents {
                        print("Document ID: \(doc.documentID)")
                        print("Document data: \(doc.data())")
                    }
                    
                    // Try to decode documents
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
                }
            }
    }
    
    // Add the loadSpace method for your ViewModel
    func loadSpace(from space: SpaceData) -> AnyPublisher<Entity, Error> {
        return Future<Entity, Error> { promise in
            guard let url = URL(string: space.usdzURL) else {
                print("⚠️ Invalid URL: \(space.usdzURL)")
                promise(.failure(SpaceServiceError.invalidURL))
                return
            }
            
            print("🔽 Downloading from URL: \(url)")
            
            URLSession.shared.downloadTask(with: url) { fileURL, response, error in
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
                    // Copy to a stable location
                    let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                    print("📁 File copied to: \(destinationURL)")
                    
                    // Load the entity
                    Entity.loadAsync(contentsOf: destinationURL)
                        .sink(receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                print("⚠️ Entity loading error: \(error)")
                                promise(.failure(error))
                            }
                        }, receiveValue: { entity in
                            print("✅ Entity loaded successfully")
                            promise(.success(entity))
                        })
                        .store(in: &self.cancellables)
                    
                } catch {
                    print("⚠️ File handling error: \(error)")
                    promise(.failure(error))
                }
            }.resume()
        }.eraseToAnyPublisher()
    }
    
    // Method for SpacesView that still uses the completion handler pattern
    func loadSpace(from space: SpaceData, completion: @escaping (Result<Entity, Error>) -> Void) {
        guard let url = URL(string: space.usdzURL) else {
            completion(.failure(SpaceServiceError.invalidURL))
            return
        }
        
        print("Downloading from URL: \(url)")
        URLSession.shared.downloadTask(with: url) { fileURL, response, error in
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
                // Copy the file from the temporary location to a stable location.
                let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
                try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                
                // Now load the entity from the copied file.
                let entity = try Entity.load(contentsOf: destinationURL)
                print("Entity loaded successfully")
                completion(.success(entity))
            } catch {
                print("Entity loading error: \(error)")
                completion(.failure(error))
            }
        }.resume()
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
