//
//  SongService.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 4/28/25.
//

import Foundation
import Combine
import FirebaseFirestore

final class SongService: ObservableObject {
    @Published var songs: [Song] = []
    private let db = Firestore.firestore(database: "uploads")
    
    init() {
        fetchSongs()
    }
    
    func fetchSongs() {
        db.collection("Music").getDocuments { [weak self] snapshot, error in
            if let error = error {
                print("❌ Failed to fetch songs:", error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("❌ No documents found")
                return
            }
            
            let songs = documents.compactMap { document in
                try? document.data(as: Song.self)
            }
            
            DispatchQueue.main.async {
                self?.songs = songs
            }
        }
    }
}
