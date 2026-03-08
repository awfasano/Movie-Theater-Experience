//
//  StoryTellerMovie.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 6/16/25.
//

import Foundation
import FirebaseFirestore

/// Represents a story document from your Firestore database.
/// Conforms to Codable for easy decoding from Firestore.
struct Story: Identifiable, Codable, Equatable, Hashable {
    // Uses the document ID from Firestore as the unique identifier.
    @DocumentID var id: String?
    
    // Fields from your Firestore document.
    var name: String
    var description: String
    var author: String
    var instructions: String
    var voice: String
    var preview: String    // RENAMED: The URL string for the story's preview image.
    var audio: String      // This will be the URL string for the audio.
    var videos: [String]   // This will be an array of URL strings for videos.
    
    // Helper property to get the first video URL.
    var videoURL: URL? {
        guard let urlString = videos.first else { return nil }
        return URL(string: urlString)
    }
    
    // Helper property to get the audio URL.
    var audioURL: URL? {
        return URL(string: audio)
    }
    
    // RENAMED: Helper property to get the preview image URL.
    var previewURL: URL? {
        return URL(string: preview)
    }
}
