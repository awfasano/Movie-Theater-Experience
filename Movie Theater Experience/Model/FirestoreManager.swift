//
//  FirestoreManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/2/25.
//

import Foundation
import FirebaseFirestore
import Combine

class FirestoreManager: ObservableObject {
    // Firestore instance for uploads (if needed)
    let uploadsDB: Firestore
    // Firestore instance for your main app (movieexperiencedb)
    let movieExperienceDB: Firestore

    init() {
        // Initialize both Firestore databases with the desired configuration.
        // Note: Adjust these initializers if you have custom settings.
        self.uploadsDB = Firestore.firestore(database: "uploads")
        self.movieExperienceDB = Firestore.firestore(database: "movieexperiencedb")
    }
    
    // You could add helper methods here for reading/writing documents,
    // e.g. a function to get a collection reference given an event ID or date.
}
