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
    // This static identifier is how the system recognizes this specific activity.
    static let activityIdentifier = "com.waitedco.Movie-Theater-Experience.PublicSpaceActivity"
    
    let spaceId: String
    let spaceName: String

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Public Call in \(spaceName)"
        metadata.subtitle = "Join the conversation!"
        
        // MODIFIED: Use .conversation for communication-based activities.
        metadata.type = .generic
        
        // NEW: This tells SharePlay that this activity is associated with a specific scene
        // (your ImmersiveSpace) identified by the string.
        metadata.sceneAssociationBehavior = .content(Self.activityIdentifier)
        
        metadata.fallbackURL = URL(string: "https://waitedco.com/spaces/\(spaceId)")
        return metadata
    }
}

/// The activity for a direct 1-on-1 call.
struct DirectCallActivity: GroupActivity {
    // This static identifier is how the system recognizes this specific activity.
    static let activityIdentifier = "com.waitedco.Movie-Theater-Experience.DirectCallActivity"
    
    let spaceId: String
    let inviter: SharePlayUser
    let invitee: SharePlayUser

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "\(inviter.name) is calling you"
        metadata.subtitle = "Join the call in the space"
        
        // MODIFIED: Use .conversation for communication-based activities.
        metadata.type = .generic
        
        // NEW: Associate this activity with its unique identifier.
        metadata.sceneAssociationBehavior = .content(Self.activityIdentifier)
        
        metadata.fallbackURL = URL(string: "https://waitedco.com/spaces/\(spaceId)")
        return metadata
    }
}

// These structs below are correct and need no changes.

/// A Codable message for synchronizing seat changes (if you ever need it).
struct UserPositionUpdate: Codable {
    let userId: String
    let newSeatId: String
}

/// A Codable message for syncing world state (good to have for future features).
struct WorldStateSyncMessage: Codable {
    let timestamp: Date
}
