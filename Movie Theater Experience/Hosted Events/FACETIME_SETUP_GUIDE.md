# FaceTime Integration Guide

## Overview

Your trivia application now uses **real Apple FaceTime Links** for table-based communication. This guide explains how the system works and how to use it.

## Architecture

### What Changed

**Before (Broken):**
- Generated fake room codes like "ABC123T01"
- Used `facetime://room/{roomCode}` URLs that don't work
- FaceTime couldn't create rooms from arbitrary codes

**After (Working):**
- Host creates real FaceTime Links using the FaceTime app
- Links stored in Firebase for each table
- Participants fetch and join real Apple FaceTime Links
- Firebase controls trivia logic separately

## How It Works

### For Hosts

1. **Start Event**: Create your trivia event as usual
2. **Set Up FaceTime Links**: Use `TableFaceTimeLinkSetupView`
   - Open FaceTime app
   - Create a new FaceTime Link for each table
   - Copy the link
   - Paste it into the setup UI
   - Save for each table
3. **Manage Event**: Run trivia as normal via Firebase

### For Participants

1. **Join Event**: Enter event and get assigned to a table
2. **Join FaceTime Call**: Use `TableFaceTimeJoinButton`
   - Button fetches the real FaceTime URL from Firebase
   - Opens FaceTime app with the link
   - Connects to table-specific call
3. **Play Trivia**: Answer questions while chatting with team

## Key Files

### Data Models
- **EventTable.swift**: Added `faceTimeLinkURL: String?` field
- Stores real FaceTime links in Firebase

### Managers
- **HostedEventManager.swift**:
  - `updateTableFaceTimeLink()`: Save FaceTime URL for a table
  - `getFaceTimeLinkForTable()`: Retrieve FaceTime URL
  - Updates both EventTable and TableVoiceRooms collection

- **HostAudioManager.swift**:
  - `joinSpecificRoom()`: Fetches real URL from Firebase
  - `joinRoomWithFetchedURL()`: Opens FaceTime with real link

### UI Components
- **TableFaceTimeLinkSetupView.swift**: Host UI to set up links
- **TableFaceTimeJoinButton.swift**: Participant button to join calls

### Activities
- **TriviaEventActivity.swift**:
  - Room code generation (for Firebase tracking only)
  - FaceTime URL methods removed (no longer valid)

## Firebase Structure

```
Events/{eventId}/
  tables/{tableNumber}/
    faceTimeLinkURL: "https://facetime.apple.com/join#v=1&p=..."
    tableNumber: 1
    teamName: "Team Alpha"
    participants: [....]

TableVoiceRooms/{roomCode}/
  faceTimeURL: "https://facetime.apple.com/join#v=1&p=..."
  roomCode: "ABC123T01"
  tableNumber: 1
  eventId: "event-123"
  isActive: true
```

## Important Notes

### What Works
✅ Real FaceTime Links created by Apple
✅ Firebase-based trivia game logic
✅ Table-specific video/audio calls
✅ Multiple tables with separate calls
✅ Host can join any table's call

### What Doesn't Work
❌ Auto-generating FaceTime rooms from codes
❌ `facetime://room/{arbitrary-code}` URLs
❌ Creating FaceTime links programmatically

### Limitations
- Host must manually create FaceTime Links
- Links must be copied/pasted into the app
- One link per table (create separately)
- FaceTime Links require Apple ID

## Usage Example

### Host Workflow
```swift
// 1. Host starts event
await hostedEventManager.joinHostedEvent(event)

// 2. Host opens TableFaceTimeLinkSetupView
// 3. For each table:
//    - Tap "Open FaceTime"
//    - Create Link in FaceTime app
//    - Copy link
//    - Paste in text field
//    - Tap "Save"

// 4. Start trivia game
await hostedEventManager.startGame()
```

### Participant Workflow
```swift
// 1. Participant joins event and gets assigned to table
await hostedEventManager.assignUserToTable(userId, tableNumber: 1)

// 2. UI shows TableFaceTimeJoinButton
// 3. Participant taps "Join Table Call"
// 4. App fetches real FaceTime URL from Firebase
// 5. FaceTime app opens with the link
// 6. Participant joins table's call
```

## Troubleshooting

### "No FaceTime link found"
- Host hasn't set up links yet
- Use `TableFaceTimeLinkSetupView` to add links

### "Failed to open FaceTime"
- Invalid URL format
- FaceTime app not available
- Check the pasted link is correct

### "Link not set up yet"
- Table exists but no FaceTime link assigned
- Host needs to complete setup

## Future Enhancements

Potential improvements:
- Auto-create FaceTime Links via API (if Apple provides)
- Host broadcast to all tables simultaneously
- Spatial audio positioning per table
- Call quality monitoring
- Automatic link rotation/refresh
