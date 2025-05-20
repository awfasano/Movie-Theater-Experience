//
//  Songs.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 4/28/25.
//

import Foundation
import Foundation
import FirebaseFirestore

struct Song: Identifiable, Codable {
    @DocumentID var id: String?
    
    /// The track title (stored in Firestore as `song`)
    var song: String
    
    /// Artist name
    var artist: String
    
    /// Download URL for the artwork image
    var artworkURL: String
    
    /// Duration in seconds
    var duration: Int
    
    /// The download URL for the MP3 file
    var storageName: String
    
    // If you’d rather call `song` “title” in your UI, you can add:
    // var title: String { song }
}
