This plan will create a system where a user can see a list of other users in the same immersive space, and from that list, initiate a direct FaceTime call, join a public call for that space, or start their own private SharePlay session.

High-Level Architectural Plan
Centralize SharePlay Logic: We will create a new singleton class, SharePlayManager, to handle all SharePlay-related tasks. This keeps the SharePlay code organized and decoupled from your views.

Track User Presence: Your existing SpaceService will be enhanced to not only know which space the local user is in but also to receive and store information about other users in the same space.

Define Group Activities: We will define multiple GroupActivity types to represent the different calling scenarios:

DirectCallActivity: For one-on-one calls.

PublicSpaceActivity: For a public, drop-in call associated with a specific spaceId.

PrivateSpaceActivity: For a new, private group call initiated by the user.

Create a User Interface: We will add new SwiftUI views:

A main button to open the list of users.

A UserListView that displays users in the current space and provides calling options.

Synchronize State: We will use GroupSessionMessenger to send essential information between users, such as their current seatId, song, and maybe interacting with the same audio story requests to join a specific call.
