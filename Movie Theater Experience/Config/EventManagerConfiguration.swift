//
//  EventManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/2/25.
//

import Foundation
import Firebase
import FirebaseFirestoreInternalWrapper

struct EventManagerConfiguration {
    /// The root collection for this event manager.
    /// For example, for movie experience you might use "Public Rooms",
    /// and for spaces you might use "Spaces".
    let rootCollection: String

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        return formatter
    }()

    /// Returns the path segments that make up the Firestore path for this event.
    func pathSegments(for eventId: String, date: Date) -> [String] {
        let dateString = EventManagerConfiguration.dateFormatter.string(from: date)
        return [rootCollection, dateString, "Events", eventId, "messages"]
    }

    /// Returns a Firestore collection reference for a given event (or space) and date.
    /// You can customize this function to build the path as needed.
    func collectionReference(db: Firestore, eventId: String, date: Date) -> CollectionReference {
        let segments = pathSegments(for: eventId, date: date)
        return db.collection(segments[0])
            .document(segments[1])
            .collection(segments[2])
            .document(segments[3])
            .collection(segments[4])
    }
}
