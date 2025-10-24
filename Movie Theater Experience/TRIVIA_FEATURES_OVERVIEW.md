# Trivia Experience Deep Dive

This guide documents the trivia-specific host and participant experiences inside **Movie Theater Experience**. It captures the layout, feature set, supporting windows, and the runtime pipeline so future discussions can build on a shared understanding.

---

## 1. Entry Flow & Role Selection

1. **Calendar Discovery** – `Hosted Events/Views/EventsCalendarView.swift` presents upcoming events and drives the selection of a `CalendarEvent`.
2. **Join Sheet** – `Hosted Events/Views/EventJoinFlowView.swift` is presented modally. It:
   - Lets the user pick `host` vs `participant`.
   - Requests the host password when needed (`hostPasswordSection` in `EventJoinFlowView.swift:232`).
   - Calls `HostedEventManager.joinHostedEvent` on confirmation (`EventJoinFlowView.swift:272`), wiring the live listeners for participants, tables, and game state.
3. **Post-Join Routing** – On success the sheet embeds either `HostExperienceView` or `ParticipantExperienceView`, both inheriting the same environment objects (`HostedEventManager.shared`, `TriviaGameManager.shared`, etc.).

---

## 2. Host Experience (Main Sheet – `HostExperienceView.swift`)

The host sheet (`HostExperienceView.swift:10`) is a tabbed console with five segments:

### 2.1 Overview Tab
- `overviewTab` (`HostExperienceView.swift:92`) displays:
  - **Event card** with icon, time range, description, and status badge.
  - **Stats grid** showing participant count, table count, current round/question if available.
  - **Quick actions** for FaceTime setup, audio room initialization, and starting the game (`HostExperienceView.swift:129`).

### 2.2 Tables Tab
- `tablesTab` (`HostExperienceView.swift:173`) lists tables using `HostTableCard` (`HostExperienceView.swift:533`):
  - Participant counts, scores, and FaceTime status.
  - Buttons to join/copy FaceTime links when configured.

### 2.3 Game Tab
- `gameTab` (`HostExperienceView.swift:218`) provides:
  - Entry point to the dedicated Host Controls window (`openWindow(id: "hostControls")`).
  - Quick game controls: next question, next round, end game.
  - A fallback “Start Game” prompt if the game hasn’t begun (`HostExperienceView.swift:296`).

### 2.4 Chat Tab
- Hosts see the shared in-event chat via `EventMessagingView` (reused with participants) when `hostedEventManager.currentEvent?.id` is available (`HostExperienceView.swift:147`).

### 2.5 Settings Tab
- `settingsTab` (`HostExperienceView.swift:338`) centralises:
  - FaceTime link setup modal toggle.
  - Placeholder for audio settings.
  - Immersive space enter/exit controls that delegate to `SpaceService` + `AppModel` for space switching.
  - Destructive “End Event” action.

Other sheet behaviour:
- “Exit” button dismisses the sheet and leaves the event.
- Alerts surface immersive launch failures (`HostExperienceView.swift:69`).

---

## 3. Host Secondary Surfaces & Tools

### 3.1 Trivia Host Controls Window
Opened from the Game tab or via `TriviaSpaceView` (`Movie Theater Experience/Core/Movie_Theater_ExperienceApp.swift:326`), the window hosts `TriviaHostControlsView` with multiple tabs:

1. **Audio Controls** – Embeds `HostMasterControlView` (tab labelled “Audio”) with room-level mixing, mute toggles, and connection indicators.
2. **Overview** – Session health (`connectionStatusCard`, `participantsCard`), SharePlay controls, and notifications (`TriviaHostControlsView.swift:80`).
3. **Game** – Deep trivia control surface:
   - Round/question management.
   - Scoreboard snapshots.
   - Per-table scoring & animation triggers via `TableControlCard` (`TriviaHostControlsView.swift:1225`).
4. **Participants** – Lists all participants, seat assignments, and Persona info (`TriviaHostControlsView.swift:901`).
5. **Broadcast** – Quick broadcast presets, templated messages, and history (`TriviaHostControlsView.swift:1021`).
6. **Debug** *(debug builds only)* – Buttons to launch Firebase/SharePlay debug windows for QA (`TriviaHostControlsView.swift:60`).

### 3.2 Quick Message Panel
- `QuickHostCommPanel` (`Hosted Events/Views/QuickHostCommPanel.swift`) opens as its own window.
- Features:
  - Category-filtered predefined messages.
  - Custom message composer with live character count.
  - Voice message recording stub.
  - Broadcast history display and “Broadcast All” FaceTime trigger (`QuickHostCommPanel.swift:57`).

### 3.3 FaceTime Link Administration
- `TableFaceTimeLinkSetupView` (sheet invoked from Overview or Settings tabs) allows the host to:
  - Generate/store FaceTime links per table.
  - Copy/share links directly.
- Each `HostTableCard` reflects status and provides “Join as Host” and “Copy link” buttons when configured (`HostExperienceView.swift:553`).

### 3.4 Diagnostics & Utilities
- `FirebaseDebugView` – surfaces raw Firestore data for troubleshooting.
- `SharePlayDiagnosticView` – introspects active Group Activities.
- `TestDataGeneratorView` – seeded under the main window menu for dev builds to populate Firestore with canned events/questions.

---

## 4. Participant Experience (`ParticipantExperienceView.swift`)

The participant sheet (`ParticipantExperienceView.swift:10`) prioritises onboarding, table selection, and answer submission:

### 4.1 Header & Global Controls
- Greeting card with Vision Pro iconography.
- Buttons for immersive entry/exit (wrapping `SpaceService.shared.fetchSpace` and `AppModel.switchToSpace`), with progress state.
- Toolbar actions:
  - “Leave” dismisses the sheet.
  - Chat button opens `EventMessagingView` in a sheet (`ParticipantExperienceView.swift:58`).

### 4.2 Current Table Section
- When the user has a table assignment:
  - Table stats (player count, score) styled in a blue card.
  - `TableFaceTimeJoinView` to launch the table’s FaceTime room (`TableFaceTimeJoinButton.swift:133`).
  - Either the active question component (`TriviaQuestionView` inside `currentQuestionSection`) or the submission workflow if no question is live.
  - Local “Game Status” card summarising round/question/progress (`ParticipantExperienceView.swift:430`).

### 4.3 Table Selection Grid
- Always visible (labelled “Choose Your Table” or “Switch Tables” depending on assignment).
- `TableSelectionCard` shows:
  - Occupancy, seating availability, and highlight if it’s the current table (`ParticipantExperienceView.swift:582`).
  - Tap to preview details; CTA button below enables joining another table (disabled when already seated).
- `joinTableButton` wraps `HostedEventManager.assignUserToTable` and prevents re-selecting current tables (`ParticipantExperienceView.swift:407`).

### 4.4 Answer Submission & Collaboration
- When no question is active, `answerSubmissionSection` offers a “Lock In Answer” CTA and displays submission state, using `HostedEventManager.submitAnswer`.
- For collaborative voting scenarios, the feature set is handled by `CollaborativeAnswerView` (`Hosted Events/Views/CollaborationAnswerView.swift`) and `TableCollaborationManager`, rendering consensus indicators, pulse animations, and per-option vote counts.

### 4.5 Additional Interactions
- FaceTime, chat, and immersive buttons remain accessible regardless of table assignment.
- `onChange(of: hostedEventManager.tables)` keeps the selection synchronised with server updates without overriding manual switches (`ParticipantExperienceView.swift:64`).

---

## 5. Trivia Runtime Pipeline

### 5.1 Game Manager
- `TriviaGameManager` (`Managers/TriviaGameManager.swift`) is the source of truth for:
  - Loading a trivia game from `TriviaGames/{id}` (`loadTriviaGame`).
  - Starting questions and running timers (`startQuestion`, `startTimer`).
  - Accepting answers (`submitAnswer`) and calculating scores (`calculateScores`) by delegating to `HostedEventManager.awardPoints`.
  - Progressing rounds/questions (`nextQuestion`, `nextRound`).

### 5.2 Hosted Event Manager
- `HostedEventManager` (`Managers/HostedEventManager.swift`) binds everything together:
  - Maintains participants, tables, and `GameState` listeners.
  - Writes seat assignments, triggers Firebase broadcasts (`triggerNotification`), and handles cleanup.
  - Coordinates persona updates so the immersive scene reflects table changes.

### 5.3 Broadcast & Animation Loop
- Hosts trigger table animations via either `TriviaHostControlsView` or `HostExperienceView` quick actions, which call `HostedEventManager.triggerNotification`.
- `TriviaImmersiveManager` listens to `Events/{id}/broadcasts` and maps messages to `TableAnimationType` enumerations, animating RealityKit entities (`Hosted Events/RealityKit/TriviaImmersiveManager.swift:192`).

---

## 6. Immersive Trivia Space

### 6.1 Loading Flow
- Host/participant `enterImmersiveSpace()` helpers fetch the event’s `spaceId`, resolve metadata via `SpaceService.shared.fetchSpace`, update `AppModel.selectedSpace/currentActiveSpace`, and call `openImmersiveSpace(id: appModel.spacesID)` (see `HostExperienceView.swift:636` & `ParticipantExperienceView.swift:500`).
- The `ImmersiveSpace` is registered in `Movie_Theater_ExperienceApp.swift:144` as `"TriviaSpace"` and presents `TriviaSpaceView`.

### 6.2 `TriviaSpaceView`
- Foundation for RealityKit content (`Hosted Events/Views/TriviaSpaceView.swift:13`):
  - `initializeSpace()` waits for the current event, then calls `TriviaImmersiveManager.setupImmersiveExperience`.
  - Handles persona seating (`PersonaTableManager`), ambient audio, overlays, and window integration (host controls, nav bar attachments).
  - Provides exit controls and error handling for immersive dismissal.

### 6.3 RealityKit Systems
- `TriviaImmersiveManager` downloads USDZ scenes (either per-event from Firebase Storage or fallback packaged assets), prepares the entity graph via `TriviaEntitySystem`, listens for broadcasts, and exposes helpers to trigger animations or fetch table entities.
- `ImmersiveQuestionBoard`, `QuickHostCommPanel`, and other overlays can project UI into the space for hosts and participants.

---

## 7. Communication & Audio Ecosystem

- **FaceTime Rooms** – Managed through `HostAudioManager` and `TableFaceTimeJoinButton`. Room codes follow the `TriviaEventActivity.generateTableRoomCode` convention. Participants fetch links live; hosts configure them via the setup sheet.
- **Quick Broadcasts** – Handled through `QuickHostCommPanel` for textual/voice announcements and `HostAudioManager.broadcastToAllRooms` for global FaceTime messaging.
- **Event Chat** – `EventMessagingView` is embedded in both host/participant sheets and operates on the shared messaging collection documented in `USER_GUIDE.md`.

---

## 8. Supporting Assets & Testing Aids

- **Test Data** – `TestDataGeneratorView` and the scripts under `Hosted Events/TestData/` (e.g., `EnhancedTriviaTestData.swift`) seed events, tables, and trivia games for local runs.
- **Guides** – Refer to:
  - `USER_GUIDE.md` for product-level instructions.
  - `TESTING_GUIDE.md` for QA scenarios.
  - `FACETIME_SETUP_GUIDE.md` for operational FaceTime steps.
  - `HOSTED_EVENTS_ARCHITECTURE.md` (companion doc) for cross-feature architecture and schema details.

---

## 9. Key Takeaways

- **Host** tooling spans the main sheet (tabs for status, tables, game controls) and secondary windows (deep controls, messaging, diagnostics). Most host actions flow through `HostedEventManager` and `TriviaGameManager`.
- **Participants** get an always-on grid for re-seating, real-time FaceTime access, and contextual trivia UI that adapts to question state.
- **Trivia runtime** is a combination of Firestore listeners (`HostedEventManager`), content/state management (`TriviaGameManager`), and RealityKit orchestration (`TriviaImmersiveManager`).
- **Immersive and audio systems** reuse the broader app infrastructure (`AppModel`, `SpaceService`, `HostAudioManager`) to ensure trivia fits within the larger movie-theater experience.

Use this reference when designing new trivia features, estimating the impacts of schema changes, or onboarding team members to the host/participant flows.
