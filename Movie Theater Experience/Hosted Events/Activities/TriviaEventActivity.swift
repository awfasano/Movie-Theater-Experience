//
//  TriviaEventActivties.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import Foundation
import GroupActivities

@available(visionOS 1.0, *)
struct TriviaEventActivity: GroupActivity {
    let eventId: String
    let eventTitle: String
    let spaceId: String
    
    var activityIdentifier: String {
        "com.yourapp.triviaEvent.\(eventId)"
    }
    
    var displayName: String { eventTitle }
    var subtitle: String? { "Join the trivia tables" }
    
    static let activityIdentifier = "com.yourapp.triviaEvent"
    
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .generic
        metadata.title = displayName
        metadata.subtitle = subtitle
        return metadata
    }
}
