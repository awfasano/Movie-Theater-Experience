//
//  EmitterService.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 11/19/24.
//

import Foundation
import FirebaseFirestore


class EmitterService {
    private let db = Firestore.firestore()
    
    func sendEmitter(dateString: String,
                     eventId: String,
                     emoji: Int,
                     seatOrTheatre: Bool,
                     senderId: String = "currentUserId",
                     senderName: String = "Anthony") {
        
        let newEmitterData: [String: Any] = [
            "timestamp": Timestamp(date: Date()),
            "senderId": senderId,
            "senderName": senderName,
            "emoji": emoji,
            "seatOrTheatre": seatOrTheatre,
            "type": false  // false indicates this is an emitter
        ]
        
        db.collection("Public Rooms")
            .document(dateString)
            .collection("Events")
            .document(eventId)
            .collection("messages")
            .addDocument(data: newEmitterData) { error in
                if let error = error {
                    print("Error sending emitter: \(error)")
                } else {
                    print("Emitter sent successfully!")
                }
            }
    }
}
