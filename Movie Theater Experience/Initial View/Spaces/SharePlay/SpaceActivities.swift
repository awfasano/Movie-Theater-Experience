//
//  SpaceActivities.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 6/28/25.
//

import GroupActivities
import Foundation

/// A simple struct to identify users in SharePlay.
/// The `name` would ideally come from a user profile service.
struct SharePlayUser: Codable, Hashable {
    let id: String // This will be the appModel.currentUserId
    let name: String
}

/// The activity for the public, drop-in call for an entire space.
struct PublicSpaceActivity: GroupActivity {
    /// The unique ID of the space this call belongs to.
    let spaceId: String
    let spaceName: String

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = NSLocalizedString("Public Call in \(spaceName)", comment: "Title for a public SharePlay call in a specific space.")
        metadata.subtitle = NSLocalizedString("Join the conversation!", comment: "Subtitle inviting users to a public call.")
        metadata.type = .generic
        // A fallback URL for users who get an invitation but don't have the app installed.
        metadata.fallbackURL = URL(string: "https://your-app-website.com/spaces/\(spaceId)")
        return metadata
    }
}

/// The activity for a direct 1-on-1 call.
struct DirectCallActivity: GroupActivity {
    let spaceId: String
    let inviter: SharePlayUser
    let invitee: SharePlayUser

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = NSLocalizedString("\(inviter.name) is calling you", comment: "Title for a direct SharePlay call invitation.")
        metadata.subtitle = NSLocalizedString("Join the call in the space.", comment: "Subtitle for a direct call invitation.")
        metadata.type = .generic
        metadata.fallbackURL = URL(string: "https://your-app-website.com/spaces/\(spaceId)")
        return metadata
    }
}

/// A Codable message for synchronizing seat changes.
struct UserPositionUpdate: Codable {
    let userId: String
    let newSeatId: String
}

struct WorldStateSyncMessage: Codable {
    // Add any properties that define the current state of your shared world.
    // For now, it can be empty if you're just syncing positions via SystemCoordinator.
    let timestamp: Date
}
