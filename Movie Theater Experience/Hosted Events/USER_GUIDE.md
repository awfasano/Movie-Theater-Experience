# Trivia Experience - Complete User Guide

## 🎉 Welcome to Your Trivia Experience!

This guide will walk you through the complete trivia experience from creating test data to playing the game.

---

## Quick Start

### Step 1: Create Test Data

1. Launch your app
2. Go to the **Events** tab in the tab bar
3. Tap the "⋯" menu in the top right
4. Select **Test Data**
5. Tap **Create Single Event** or **Create 3 Events**
6. Wait for the success message

**What this creates:**
- ✅ A trivia event with 6 tables (4 seats each)
- ✅ A trivia game with 3 rounds and 5 questions per round
- ✅ All necessary Firebase data

### Step 2: Join an Event

1. You'll see the test event in the Events list
2. Tap on the event card
3. Choose your role:
   - **Host**: Control the event (requires password: `trivia123`)
   - **Participant**: Play trivia with friends

### Step 3: Set Up FaceTime (Host Only)

1. If you joined as **Host**, tap "Set Up FaceTime Links"
2. For each table:
   - Tap "Open FaceTime"
   - Create a FaceTime Link in the FaceTime app
   - Copy the link
   - Paste it into the text field
   - Tap "Save"

### Step 4: Play!

**As Host:**
- Start the game
- Control rounds and questions
- Monitor all tables
- Join any table's FaceTime call

**As Participant:**
- Select a table to join (choose one with friends!)
- Tap "Join Table Call" to connect via FaceTime
- Answer questions with your team
- See your score in real-time

---

## Detailed Feature Guide

### Events Calendar

**Location:** Events tab in the bottom tab bar

**Features:**
- 📅 View all upcoming trivia events
- 🔍 Events grouped by date (Today, Tomorrow, etc.)
- 📊 See participant count and event status
- 🎯 Quick join from event cards

**Event Status Badges:**
- **Scheduled** (Blue): Event hasn't started yet
- **Active** (Green): Event is happening now
- **Ended** (Gray): Event has finished
- **Cancelled** (Red): Event was cancelled

### Host Experience

**Password:** `trivia123` (for testing)

#### Overview Tab
- **Event Information**: Title, time, description
- **Quick Stats**: Participants, tables, round, question
- **Quick Actions**:
  - Set Up FaceTime Links
  - Initialize Audio Rooms
  - Start Game

#### Tables Tab
- View all tables and their status
- See participant count per table
- Check which tables have FaceTime links configured
- Monitor table scores

#### Game Tab
- **Game Controls**:
  - Next Question: Advance to next question
  - Next Round: Move to next round
  - End Game: Finish the event
- View current round and question
- See game status (Waiting, Active, Finished)

#### Settings Tab
- FaceTime Link Setup
- Audio Settings
- End Event (destructive action)

### Participant Experience

#### Table Selection
- **Visual Table Grid**: See all available tables
- **Occupancy Info**: Shows `X/4` participants
- **Status Indicators**:
  - Green: "X seats left"
  - Red: "Full"
- **Team Names**: Each table has a unique name:
  - Thunder Squad
  - Brain Busters
  - Quiz Masters
  - The Thinkers
  - Trivia Titans
  - Knowledge Ninjas

#### Once at a Table
- **Table Info Card**: Shows your table name and member count
- **FaceTime Join Button**: Connect to your table's call
- **Game Status**: See current round/question
- **Score Display**: Track your table's points

### FaceTime Integration

#### Setting Up Links (Host)
1. Open `TableFaceTimeLinkSetupView` from host controls
2. For each table:
   ```
   Open FaceTime → Create Link → Copy → Paste → Save
   ```
3. Green checkmark appears when link is set

#### Joining Calls (Participant)
1. Join your table first
2. Tap **Join Table Call** button
3. FaceTime opens automatically
4. Connect with your teammates!

**Status Messages:**
- "Join Table Call" (Blue): Ready to join
- "No FaceTime link available" (Gray): Host hasn't set it up yet
- "Failed to open FaceTime" (Red): Check your link or connection

---

## Complete Walkthrough

### Scenario: Host a Trivia Night

**Time Required:** ~10 minutes setup, 30-60 minutes gameplay

#### Pre-Event (5-10 minutes)

1. **Create Event** (if testing)
   ```
   Events Tab → Menu → Test Data → Create Single Event
   ```

2. **Join as Host**
   ```
   Tap Event → Select "Host" → Enter password: trivia123 → Join
   ```

3. **Set Up FaceTime Links**
   ```
   Overview Tab → Set Up FaceTime Links
   For each of 6 tables:
     - Open FaceTime app
     - Create Link
     - Copy link
     - Paste in app
     - Save
   ```

4. **Initialize Audio Rooms**
   ```
   Overview Tab → Initialize Audio Rooms
   ```

5. **Start Game**
   ```
   Overview Tab → Start Game
   OR
   Game Tab → Start Game
   ```

#### During Event (30-60 minutes)

1. **Monitor Participants**
   ```
   Tables Tab → View all tables and participants
   ```

2. **Control Game Flow**
   ```
   Game Tab → Next Question (after each question)
   Game Tab → Next Round (after each round)
   ```

3. **Join Table Calls** (optional)
   ```
   Use HostAudioManager to join specific table calls
   Listen to teams discuss answers
   ```

4. **Send Notifications** (optional)
   ```
   Use triggerNotification() to send messages to all participants
   ```

#### Post-Event

1. **End Game**
   ```
   Game Tab → End Game
   OR
   Settings Tab → End Event
   ```

2. **View Results**
   ```
   Tables Tab → See final scores
   ```

### Scenario: Join as Participant

**Time Required:** ~5 minutes setup, 30-60 minutes gameplay

#### Joining (2-3 minutes)

1. **Browse Events**
   ```
   Events Tab → View available trivia nights
   ```

2. **Join Event**
   ```
   Tap Event Card → Select "Participant" → Join
   ```

3. **Select Table**
   ```
   View available tables
   Choose table with friends or available seats
   Tap table → Join Table [Name]
   ```

4. **Connect FaceTime**
   ```
   Tap "Join Table Call"
   FaceTime opens
   Connect to your team
   ```

#### Playing (30-60 minutes)

1. **See Questions**
   ```
   Questions appear from the host
   Discuss with your table via FaceTime
   ```

2. **Submit Answers**
   ```
   Vote on answer with your team
   Submit team's final answer
   ```

3. **Track Progress**
   ```
   View your table's score
   See current round/question
   ```

4. **Switch Tables** (optional)
   ```
   Leave current table
   Select new table from grid
   Join new table's FaceTime call
   ```

---

## Test Data Details

### Test Event Specifications

**Event:**
- Title: "🎯 Friday Night Trivia"
- Duration: 1 hour
- Start: 5 minutes from creation
- Max Participants: 24

**Tables:**
- 6 tables total
- 4 seats per table
- Circular layout
- Pre-named teams

**Trivia Game:**
- 3 rounds
- 5 questions per round
- 30 seconds per question
- 10 points per correct answer

**Sample Questions:**
1. What is the capital of France?
2. How many planets are in our solar system?
3. Who painted the Mona Lisa?
4. What year did World War II end?
5. What is the largest ocean on Earth?

### Creating Multiple Events

```
Test Data → Create 3 Events
```

This creates 3 identical events on consecutive days:
- Event 1: Today + 5 minutes
- Event 2: Tomorrow + 5 minutes
- Event 3: Day after tomorrow + 5 minutes

### Deleting Test Data

```
Test Data → Delete All Test Events
```

**Warning:** This deletes ALL events and related data!

---

## Troubleshooting

### Common Issues

#### "No events available"
**Solution:** Create test data via Events → Menu → Test Data

#### "Incorrect password"
**Solution:** Use `trivia123` (all lowercase)

#### "No FaceTime link available"
**Solution:** Host needs to set up links first

#### "Failed to join table"
**Solution:**
- Table might be full (check participant count)
- Try a different table
- Ask host to restart event

#### "FaceTime won't open"
**Solution:**
- Ensure you're signed into FaceTime
- Check if host set up the link for your table
- Try leaving and rejoining the table

#### Tables not showing up
**Solution:**
- Host needs to create/load the event properly
- Refresh the events list
- Try recreating test data

### Debug Information

**Firebase Collections:**
- `Events/{eventId}` - Event data
- `Events/{eventId}/tables/{tableNumber}` - Table data
- `Events/{eventId}/participants/{userId}` - Participant data
- `TableVoiceRooms/{roomCode}` - FaceTime link data
- `TriviaGames/{gameId}` - Trivia questions

**Console Logs to Look For:**
- ✅ Success messages (green)
- ❌ Error messages (red)
- ⚠️ Warning messages (yellow)
- 🎮 Game events
- 📞 FaceTime operations
- 🪑 Table assignments

---

## Advanced Features

### Host Controls

#### Broadcast to All Tables
```swift
HostAudioManager.shared.broadcastToAllRooms()
```

#### Join Specific Table
```swift
HostAudioManager.shared.joinSpecificRoom(roomCode)
```

#### Send Notifications
```swift
await hostedEventManager.triggerNotification("Get ready!")
```

### Custom Game Configuration

Modify `GameConfiguration` in test data:
```swift
GameConfiguration(
    triviaGameId: "custom-game",
    totalRounds: 5,           // Change round count
    pointsPerQuestion: 15,    // Change point values
    questionTimeLimit: 45     // Change time limits
)
```

### Custom Table Layout

Modify `TableConfiguration`:
```swift
TableConfiguration(
    maxTables: 8,              // Change table count
    maxSeatsPerTable: 6,       // Change seats per table
    layoutType: .classroom     // Change layout style
)
```

---

## API Reference

### Key Managers

**HostedEventManager**
- `joinHostedEvent(_:)` - Join an event
- `assignUserToTable(_:tableNumber:)` - Assign user to table
- `updateTableFaceTimeLink(_:faceTimeURL:)` - Set FaceTime link
- `startGame()` - Begin trivia game
- `endGame()` - End trivia game

**TriviaGameManager**
- `loadTriviaGame(_:)` - Load trivia questions
- `startQuestion(_:)` - Begin a question
- `nextQuestion()` - Advance to next question
- `nextRound()` - Advance to next round

**HostAudioManager**
- `joinSpecificRoom(_:)` - Join table's FaceTime call
- `leaveRoom(_:)` - Leave current call
- `broadcastToAllRooms()` - Broadcast to all tables

**TriviaTestDataGenerator**
- `createTestTriviaEvent()` - Create single test event
- `createMultipleTestEvents(count:)` - Create multiple events
- `deleteAllTestEvents()` - Delete all test data

---

## Tips & Best Practices

### For Hosts

1. **Set up FaceTime links BEFORE the event starts**
2. **Test joining one table's call** to verify links work
3. **Initialize audio rooms** before starting the game
4. **Monitor the Tables tab** to see participant distribution
5. **Use Game tab controls** to maintain steady game flow
6. **End the game properly** to save statistics

### For Participants

1. **Join early** to get your preferred table
2. **Coordinate with friends** on which table to join
3. **Test FaceTime** before the game starts
4. **Stay on the Game Status screen** during gameplay
5. **Communicate with your team** via FaceTime

### Testing Tips

1. **Use multiple devices** to test full experience
2. **Create test events** on different days to avoid conflicts
3. **Delete old test data** regularly to keep Firebase clean
4. **Check console logs** when debugging issues
5. **Test the full flow** from event creation to game end

---

## What's Next?

Future enhancements planned:
- Real-time question display
- Live leaderboard
- Answer submission UI
- Team chat integration
- Spatial audio positioning
- Achievement system
- Event history & replays

---

## Support

**Issues or Questions?**
- Check console logs for error messages
- Review `FACETIME_SETUP_GUIDE.md` for FaceTime details
- Review `TESTING_GUIDE.md` for testing strategies
- Check Firebase Console for data issues

**File Locations:**
- Events: `/Hosted Events/Views/EventsCalendarView.swift`
- Join Flow: `/Hosted Events/Views/EventJoinFlowView.swift`
- Host Experience: `/Hosted Events/Views/HostExperienceView.swift`
- Participant Experience: `/Hosted Events/Views/ParticipantExperienceView.swift`
- Test Data: `/Hosted Events/TestData/TriviaTestDataGenerator.swift`
