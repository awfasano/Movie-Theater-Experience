//
//  EventManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/2/25.
//

import Foundation
import Firebase

enum FirebaseConfig {
    static let databaseID = "movieexperiencedb"
    static let uploadsDatabaseID = "uploads"
}

struct EventManagerConfiguration {
    /// The root collection for this event manager.
    /// For example, for movie experience you might use "Public Rooms",
    /// and for spaces you might use "Spaces".
    let rootCollection: String

    /// Returns a Firestore collection reference for a given event (or space) and date.
    /// You can customize this function to build the path as needed.
    func collectionReference(db: Firestore, eventId: String, date: Date) -> CollectionReference {
        // For example, using:
        // [rootCollection] -> [formatted date] -> [Events] -> [eventId] -> messages
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        let dateString = formatter.string(from: date)
        return db.collection(rootCollection)
            .document(dateString)
            .collection("Events")
            .document(eventId)
            .collection("messages")
    }
}
