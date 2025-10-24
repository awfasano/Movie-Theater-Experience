# Hosted Events Architecture Guide

This document explains how the Hosted Events feature set is organised inside the `Hosted Events/` directory and how it plugs into the wider **Movie Theater Experience** application. It is intended for engineers who need to debug, extend, or onboard new teammates to the trivia-hosting workflow.

---

## 1. Application Architecture Snapshot

The app is built as a multi-window visionOS experience:

- `Movie_Theater_ExperienceApp.swift` bootstraps Firebase, sets up `AppModel.shared`, and registers multiple `WindowGroup` and `ImmersiveSpace` scenes (`Movie Theater Experience/Core/Movie_Theater_ExperienceApp.swift:1`).
- `AppModel` (`Movie Theater Experience/Core/AppModel.swift`) is the primary observable state. It tracks the active immersive space, user identity, selected volumes, and global window coordination.
- Shared infrastructure (Firebase clients, Seat selection, ImmersiveSpaceManager, WindowManager, SpacesEntityWrapper) lives under `Core/`, `Config/`, `Initial View/Spaces/`, and `Immersive/`.
- Hosted Events builds on the same shared services. It reuses:
  - `AppModel` for immersive coordination and user identity.
  - `ImmersiveSpaceManager.shared` for immersive lifecycle.
  - `SpaceService.shared` to download USDZ spaces from Firebase Storage.
  - Window helpers (`WindowManager`, `WindowType`) to open auxiliary host/participant tools.

The architecture follows a **feature folder** approach: views, models, and services for Hosted Events stay inside `Hosted Events/`, while shared types live elsewhere.

---

## 2. Hosted Events Overview

Hosted Events enables organisers to run live, table-based trivia games:

1. **Discover & select an event** (`EventsCalendarView.swift`).
2. **Join flow** collects role (host vs participant) and host password (`EventJoinFlowView.swift`).
3. **Host experience** offers dashboards, scoring, FaceTime controls, messaging, and immersive triggers (`HostExperienceView.swift`, `TriviaHostControlsView.swift`, `QuickHostCommPanel.swift`, etc.).
4. **Participant experience** guides seat selection, answer submission, and immersive entry (`ParticipantExperienceView.swift`).
5. **Immersive space** renders the Trivia arena in RealityKit (`TriviaSpaceView.swift`, `Hosted Events/RealityKit/`).
6. **Live sync**: Firebase Firestore stores event state, participants, tables, scores, broadcasts, and trivia content. Managers observe this data and update SwiftUI/UI windows.
7. **Audio & collaboration**: FaceTime links, SharePlay activities, and table voice rooms managed via Firestore documents (`HostAudioManager.swift`, `TableFaceTimeLinkSetupView.swift`).

---

## 3. Directory Layout

```
Hosted Events/
├─ Activities/                 # GroupActivity definitions (SharePlay session codes, room IDs)
├─ Managers/                   # ObservableObject singletons that orchestrate state + Firebase
├─ Models/                     # Codable structs for Firestore documents (events, tables, questions)
├─ RealityKit/                 # Trivia RealityKit scene management and entity systems
├─ TestData/                   # Local generators and fixtures for dev/testing
├─ Views/                      # SwiftUI views for host, participant, join flow, dashboards, etc.
├─ FACETIME_SETUP_GUIDE.md     # Operational docs focused on FaceTime integration
├─ TESTING_GUIDE.md            # QA workflow for Hosted Events
├─ TRIVIA_QUESTION_EXAMPLES.md # Sample trivia payloads
├─ USER_GUIDE.md               # Product-level walkthrough
└─ HOSTED_EVENTS_ARCHITECTURE.md# (this file)
```

---

## 4. Core Data & Firebase Schema

Hosted Events data lives in Firestore (database: `uploads`):

| Collection / Doc                  | Purpose                                                                                          |
|----------------------------------|--------------------------------------------------------------------------------------------------|
| `Events/{eventId}`               | Root event metadata (`CalendarEvent`, see `Movie Theater Experience/Model/CalendarEvent.swift`). |
| `Events/{eventId}/participants`  | `EventParticipant` docs: user id, role, seat/table assignment.                                   |
| `Events/{eventId}/tables`        | `EventTable` docs: teams, participants, seat positions, FaceTime link, scores.                   |
| `Events/{eventId}/gameState`     | Single `current` doc describing `GameState` (round, question, aggregate scores).                |
| `Events/{eventId}/broadcasts`    | Fire-and-forget host messages (e.g., `table_3_celebrate`) consumed by `TriviaImmersiveManager`. |
| `Events/{eventId}/submissions`   | Table answers per question.                                                                      |
| `TableVoiceRooms/{roomCode}`     | Audio routing metadata + FaceTime URLs for HostAudioManager.                                     |
| `TriviaGames/{gameId}`           | Trivia content loaded by `TriviaGameManager`.                                                     |
| `Spaces/{spaceId}`               | Reusable immersive environments fetched by `SpaceService.shared`.                                |

> The managers translate these Firestore documents into in-memory `@Published` state so SwiftUI views and RealityKit scenes react automatically.

### 4.1 Detailed Firebase Schema

The Hosted Events feature relies on a consistent Firestore structure. The following table captures each collection, with data types, whether the field is optional, sample values, and notes on how the client uses the data. Keep this schema in sync with changes to the models in `Hosted Events/Models/`.

#### 4.1.1 `Events` Collection

| Path / Field | Type | Required | Example | Notes |
|--------------|------|----------|---------|-------|
| `Events/{eventId}` | Document | ✅ | `"trivia-night-2025-05-18"` | Mirrors `CalendarEvent`. Created by the backend or tooling. |
| ├─ `title` | String | ✅ | `"Friday Night Trivia"` | Displayed in calendars and headers. |
| ├─ `description` | String | ✅ | Text summary | Used in join flow + marketing. |
| ├─ `startTime`, `endTime` | Timestamp | ✅ | `2025-05-18T20:00Z` | ISO timestamps in UTC. |
| ├─ `maxParticipants`, `currentParticipants` | Int | ✅ | `120`, `47` | `currentParticipants` maintained by backend or cloud function. |
| ├─ `spaceId` | String | ❌ | `"space-bar"` | Links to `Spaces/{spaceId}` for immersive scene. |
| ├─ `hostPassword` | String | ❌ | `"trivia123"` | Used by `EventJoinFlowView`; may be hashed in production. |
| ├─ `eventType` | String | ✅ | `"trivia"` | Enables future reuse for other event types. |
| └─ `gameConfig` | Map | ❌ | `{ "triviaGameId": "game_2025_01", "rounds": 3 }` | Passed to `TriviaGameManager`. |

##### 4.1.1.a `participants` Subcollection

| Field | Type | Required | Example | Notes |
|-------|------|----------|---------|-------|
| `userId` | String | ✅ | `"user_abc123"` | Primary key (mirrors document ID). |
| `userName` | String | ✅ | `"Alex"` | Display label for chat + UI. |
| `role` | String | ✅ | `"host"` / `"participant"` | Drives UI gating. |
| `tableNumber` | Int | ❌ | `3` | Current table assignment; nullable before seating. |
| `seatIndex` | Int | ❌ | `1` | Seat within table; used by `PersonaTableManager`. |
| `personaAnchor` | String | ❌ | `"table3_seat1"` | Anchor ID in immersive space. |
| `joinedAt` | Timestamp | ✅ | | Audit + ordering. |

Indexes: Query on `role`, occasionally on `tableNumber`. Configure composite index if sorting/filtering is needed.

##### 4.1.1.b `tables` Subcollection

| Field | Type | Required | Example | Notes |
|-------|------|----------|---------|-------|
| `tableNumber` | Int | ✅ | `3` | Document ID is stringified number (`"3"`). |
| `teamName` | String | ❌ | `"The Popcorn Crew"` | Displayed in host/participant UI. |
| `participants` | Array<String> | ✅ | `["user_abc123", …]` | Raw user IDs; used for quick occupancy. |
| `maxSeats` | Int | ✅ | `8` | |
| `currentScore` | Int | ✅ | `25` | Updated by host scoring. |
| `faceTimeLinkURL` | String | ❌ | `https://facetime.apple.com/join#ABC...` | Set via host UI. |
| `tablePosition` | Map | ✅ | `{ "x": 0.5, "y": 0.0, "z": -2.0 }` | Used by immersive scene to place tables. |
| `seatPositions` | Map<String, Map> | ✅ | `{ "0": {x: …}, … }` | Seat transforms keyed by string index; avoid nested arrays. |

Indexes: Typically listen to entire collection; no special index required.

##### 4.1.1.c `gameState` Subcollection (Document `"current"`)

| Field | Type | Required | Example | Notes |
|-------|------|----------|---------|-------|
| `currentRound` | Int | ✅ | `2` | Host increments. |
| `status` | String | ✅ | `"question_active"` | Enum defined in `GameStatus`. |
| `currentQuestion` | Int | ❌ | `5` | Number within round; optional during waiting states. |
| `scores` | Map<String, Int> | ✅ | `{ "1": 30, "2": 20 }` | TableNumber → cumulative score. |
| `trigger` | String | ❌ | `"table_2_celebrate"` | Last broadcast animation trigger; consumed by immersive manager. |
| `updatedAt` | Timestamp | ✅ | | Ensure consistent ordering. |

Indexes: Single-document lookups; no index needed.

##### 4.1.1.d `broadcasts` Subcollection

| Field | Type | Required | Example | Notes |
|-------|------|----------|---------|-------|
| `message` | String | ✅ | `"table_3_correct_answer"` | Pattern: `table_{number}_{animation}` or general signals. |
| `type` | String | ✅ | `"instruction"` | Reserved for future (e.g., `"system"`). |
| `hostId` | String | ✅ | | Who triggered the broadcast. |
| `timestamp` | Timestamp | ✅ | | Snapshot listener orders by this field. |

Indexes: Ensure ordered queries (`orderBy timestamp`). Add TTL cleanup policy if needed.

##### 4.1.1.e `submissions` Subcollection

| Field | Type | Required | Example | Notes |
|-------|------|----------|---------|-------|
| `tableNumber` | Int | ✅ | `4` | |
| `questionId` | String | ✅ | `"round1_q2"` | |
| `answer` | Int | ✅ | `1` | Index of selected answer. |
| `points` | Int | ✅ | `10` | Calculated by TriviaGameManager. |
| `timestamp` | Timestamp | ✅ | | Used for tie-breakers. |

Indexes: Composite index on `questionId` + `tableNumber` recommended for analytics.

#### 4.1.2 `TableVoiceRooms` Collection

| Field | Type | Required | Example | Notes |
|-------|------|----------|---------|-------|
| `roomCode` | Document ID | ✅ | `"ABC123T01"` | Derived from `TriviaEventActivity`. |
| `eventId` | String | ✅ | `"trivia-night-2025-05-18"` | Back-reference for cleanup. |
| `tableNumber` | Int | ❌ | `1` | Absent for host broadcast room. |
| `faceTimeURL` | String | ✅ | Real FaceTime link | Managed via host setup screen. |
| `participants` | Array<String> | ❌ | `[ "user_abc123" ]` | Currently informational. |
| `lastActive` | Timestamp | ✅ | | Updated by heartbeat or join/leave. |
| `status` | String | ❌ | `"connected"` | Exposed in dashboards. |

Indexes: Single document lookups by ID. Optional index on `eventId` for cleanup queries.

#### 4.1.3 `TriviaGames` Collection

Models the trivia catalog loaded by `TriviaGameManager`.

| Field | Type | Required | Example | Notes |
|-------|------|----------|---------|-------|
| `title` | String | ✅ | `"Movie Soundtracks"` | |
| `description` | String | ❌ | `"Guess the film from the score"` | |
| `rounds` | Array<Map> | ✅ | Each map: `{ "title": "Round 1", "questions": [ … ] }` | Decoded into `TriviaGame.rounds`. |
| `currentQuestionIndex` | Int | ✅ | `0` | Maintained by manager when resuming games. |
| `createdAt` / `updatedAt` | Timestamp | ✅ | | Used for sorting. |

Each question map typically contains:

| Field | Type | Example |
|-------|------|---------|
| `id` | String | `"round1_q1"` |
| `questionText` | String | `"Which film features this theme?"` |
| `answers` | Array<String> | `["Star Wars", …]` |
| `correctAnswer` | Int | `0` |
| `points` | Int | `10` |
| `timeLimit` | Int | `45` |

#### 4.1.4 `Spaces` Collection

Shared immersive spaces leveraged by Hosted Events and other app surfaces.

| Field | Type | Required | Example | Notes |
|-------|------|----------|---------|-------|
| `spaceName` | String | ✅ | `"Space Bar"` |
| `description` | String | ✅ | `"Zero-g lounge with music"` |
| `usdzURL` | String | ✅ | Firebase Storage URL | Downloaded by `SpaceService.shared`. |
| `thumbnailURL` | String | ❌ | | Used in space browser. |
| `mapURL` | String | ❌ | | Seat map overlay. |
| `ambient_audio` | String | ❌ | File ID for ambient soundtrack. |
| `tags` | Array<String> | ❌ | `["music", "social"]` | Filter in UI. |
| `viewerXAdjustment`, `viewerYAdjustment`, `viewerZAdjustment` | Double | ✅ | Offsets for anchoring user. |
| `volumeInitialScale`, `volumeOffsetX/Y/Z` | Double | ❌ | Tuning for volumetric preview. |
| `seats` | Array<Map> | ❌ | Seat metadata (id, label, transform). |
| `currentUserCount`, `maxUserCount` | Int | ✅ | Live occupancy. |
| `lastModified` | Timestamp | ✅ | |

Indexes: Queries often filter by `tags` or order by `lastModified`. Configure composite indexes as needed.

---

---

## 5. Shared Models (`Models/`)

Key Codable structs:

- `EventParticipant.swift`: role (`.host`, `.participant`), table/seat indices, persona metadata.
- `EventTable.swift`: table layout, occupancy, FaceTime link, and seat transforms. Uses `Position3D` wrappers to avoid encoding SIMD types.
- `GameState.swift`, `TriviaGame.swift`, `TriviaQuestion.swift`: scoreboard and trivia content.
- `HostedEventError.swift`: domain-specific error cases surfaced to the UI.

These models are used both by managers (for decoding Firestore) and by UI views.

---

## 6. Manager Layer (`Managers/`)

All managers are `@MainActor` singletons to keep SwiftUI updates on the main thread.

### 6.1 `HostedEventManager` (`Managers/HostedEventManager.swift`)

- **Responsibilities:** Join/leave events, keep participants/tables/game state in sync, manage Firebase listeners, assign seats, push host notifications, orchestrate cleanup.
- **Inputs:** `CalendarEvent`, Firestore snapshots, `AppModel.shared.currentUserId`.
- **Outputs:** `@Published` arrays for participants, tables, and `GameState`.
- **Collaborators:** `PersonaTableManager` (updates avatars in immersive scene), `HostAudioManager`, `TriviaGameManager`.
- **Side effects:** Writes to `Events/{id}` subcollections; triggers `registerAudioRoomForTable`; updates persona positions when local user changes tables.

### 6.2 `TriviaGameManager` (`Managers/TriviaGameManager.swift`)

- **Responsibilities:** Load trivia content, run timers, start/end questions, submit answers, calculate scores by delegating to `HostedEventManager`.
- **Firebase:** Reads `TriviaGames`, writes submissions to `Events/{id}/submissions`.

### 6.3 `PersonaTableManager` & `ParticipantTableManager`

- Provide mapping between participants and table/seat geometry for both 2D UI and RealityKit. Integrates with `TriviaImmersiveManager` to position avatars.

### 6.4 `HostAudioManager`

- Manages FaceTime room metadata, broadcast state, muting, and external URL opening. Reads/writes `TableVoiceRooms`, monitors room activity, and exposes connection state for host dashboards.

### 6.5 `ConnectionManager` & `TableCollaborationManager`

- Offer ancillary collaboration features (e.g., transient host announcements, collaborative answer flows). They coordinate with `HostedEventManager` to ensure consistent state and manage Combine publishers.

### 6.6 `TriviaImmersiveManager` (`RealityKit/TriviaImmersiveManager.swift`)

- Bridges RealityKit and Firebase: loads USDZ scenes, prepares table entities, listens to `broadcasts` for animation triggers, and exposes helper APIs to host/participant views.
- Collaborates with `TriviaEntitySystem` (entity graph utilities) and `TriviaSpaceView` (RealityView host).
- Requests spaces from Firebase Storage via `SpaceService.shared`, caches, and injects them into the RealityKit scene.

---

## 7. SwiftUI Views (`Views/`)

The view layer is organised by workflow:

### 7.1 Discovery & Entry

- `EventsCalendarView.swift`: Calendar of upcoming events, loads via `FirebaseEventManager`.
- `EventJoinFlowView.swift`: Role selection, host password gate, asynchronous join via `HostedEventManager`.
- `EventMessagingView.swift`: Realtime chat per event (reused by host and participant overlays).

### 7.2 Host Console

- `HostExperienceView.swift`: Primary host dashboard (tables, scoring, FaceTime setup, immersive triggers).
- `TriviaHostControlsView.swift`, `HostMasterControlView.swift`: Detailed game management (round progression, per-table scoring, animations).
- `QuickHostCommPanel.swift`: Predefined messages and voice recordings triggered to participants.
- `TableFaceTimeLinkSetupView.swift`, `TableRoomControlCard.swift`: Manage per-table FaceTime links and voice rooms.
- `FirebaseDebugView.swift`, `SharePlayDiagnosticView.swift`: Diagnostics and developer tooling windows for Firebase & SharePlay.

### 7.3 Participant Experience

- `ParticipantExperienceView.swift`: Table selection, chat, immersive entry, answer submission.
- `ParticipantSpatialUI.swift`, `PersonaTableSelectionView.swift`: Persona placement and seat selection UI.
- `TableQuestionPanel.swift`, `CollaborationAnswerView.swift`: Coordinated answer submission UI.

### 7.4 Shared Components

- `TriviaQuestionView.swift`, `RoundRowView.swift`, `TrophyView.swift`, `WinnerAnnouncementView.swift`, `ConfettiView.swift`: UI building blocks used by both roles for progress, celebration, or overlays.
- `ImmersiveQuestionBoard.swift`: 2D overlays projected into the immersive space.

### 7.5 Immersive View

- `TriviaSpaceView.swift`: RealityView container that loads `TriviaImmersiveManager`, sets up anchors, handles persona placement, and listens for Firebase events.

---

## 8. RealityKit Layer (`RealityKit/`)

- `TriviaImmersiveManager.swift`: Manages the immersive scene life cycle (load, teardown, broadcast listeners).
- `TriviaEntitySystem.swift`: Generates or reconfigures table entities, seat locations, and handles animation triggering.
- Supporting utilities map FaceTime participants to 3D entities, handle ambient audio, and sync overlays into the scene.

The immersive space can be sourced either from bundled RealityKit assets or from USDZ scenes stored in Firebase Storage. Hosted events now rely on `SpaceService.shared.fetchSpace(withId:)` so the same immersive spaces used elsewhere in the app can be reused for trivia.

---

## 9. Activities (`Activities/`)

- `TriviaEventActivity`: Implements `GroupActivity` for SharePlay. Generates consistent session codes and room identifiers, enabling host/participants to stay in sync during SharePlay sessions. Collaborates with `HostAudioManager` and `HostedEventManager` when creating table voice rooms or broadcast sessions.

---

## 10. Test & Debug Utilities

- `TestDataGeneratorView.swift` + `TestData` folder: Populate Firestore with sample events, tables, and trivia content for local development.
- `FirebaseDebugView.swift`: Surface Firestore listeners and sanity checks.
- `TESTING_GUIDE.md`: Manual QA checklist for verifying host/participant flows, immersive entry, and audio.
- `TRIVIA_QUESTION_EXAMPLES.md`: Ready-made trivia payloads to seed Firestore.
- `USER_GUIDE.md`: High-level functional description for non-engineering stakeholders.

---

## 11. Data & Event Flow

1. **Event selection**: `EventsCalendarView` loads `CalendarEvent` documents via `FirebaseEventManager`. Selecting an event presents `EventJoinFlowView`.
2. **Join**: Depending on role, `EventJoinFlowView` calls `HostedEventManager.joinHostedEvent`. This writes a participant doc and sets up listeners (participants, tables, gameState).
3. **State propagation**:
   - `HostedEventManager` updates `@Published` arrays.
   - `HostExperienceView` and `ParticipantExperienceView` observe these environment objects and refresh UI accordingly.
   - `TriviaGameManager` listens to `GameState` updates and loads trivia content as needed.
4. **Table management**:
   - Host or participants trigger `assignUserToTable`.
   - Firestore updates propagate to all clients; `PersonaTableManager` adjusts immersive avatars.
5. **Game control**:
   - Hosts use `TriviaHostControlsView` to advance rounds/questions, award points, or clear submissions.
   - Participants submit answers; `HostedEventManager` writes to Firestore; `TriviaGameManager` calculates scores.
6. **Broadcasts & animations**:
   - Host triggers `HostedEventManager.triggerNotification("table_3_celebrate")`.
   - `TriviaImmersiveManager` listens to `broadcasts` and triggers the corresponding `TableAnimationType` inside RealityKit.
7. **Immersive entry**:
   - Host/participant views call `enterImmersiveSpace()` which:
     1. Resolves the event’s `spaceId`.
     2. Fetches `SpaceData` via `SpaceService.shared.fetchSpace`.
     3. Updates `AppModel.selectedSpace/currentActiveSpace`.
     4. Requests `AppModel.switchToSpace(appModel.spacesID)`.
     5. Opens the `ImmersiveSpace` defined in `Movie_Theater_ExperienceApp`.
   - `TriviaSpaceView` then loads the 3D scene via `TriviaImmersiveManager.setupImmersiveExperience`.
8. **Audio & FaceTime**:
   - Host configures FaceTime links per table (`TableFaceTimeLinkSetupView`).
   - `HostAudioManager` reads/writes `TableVoiceRooms` documents, launches FaceTime sessions, and tracks broadcast state.
9. **Messaging & collaboration**:
   - `EventMessagingView` surfaces event-wide chat.
   - `QuickHostCommPanel` and `TableCollaborationManager` coordinate canned messages and collaborative answer prompts.

---

## 12. Integration Points with Other Modules

- **AppModel**: Single source of truth for user IDs, current event, active immersive space.
- **SpaceService** and **SpacesView**: Hosted events reuse the shared space browser pipeline to load and present immersive USDZ scenes.
- **ImmersiveSpaceManager**: Ensures only one immersive experience is active and handles cleanup when switching between trivia and other app spaces.
- **WindowManager**: Host actions open additional windows (e.g., Table dashboards, audio controls) using shared window tracking.
- **Config Window Types**: Hosted events use dedicated `WindowType` IDs to open/close supporting windows.
- **SharePlayManager**: Coordinates Group Activities, ensuring participants in the immersive space stay synchronised.

---

## 13. Extensibility Guidelines

When adding new features:

1. **Models**: Extend the relevant Codable struct and ensure Firestore writes include the new fields. Update decoding logic in managers.
2. **Firebase schema**: Document new collections or fields. Update `TESTING_GUIDE.md` if manual setup is required.
3. **Managers**: Keep them focused; if a new concern emerges (e.g., achievements), create a dedicated manager and inject it via environment objects.
4. **Views**: Place new host/participant screens in `Views/`. Mirror the existing environment object usage (`@EnvironmentObject HostedEventManager` & `TriviaGameManager`) for consistency.
5. **RealityKit**: Extend `TriviaEntitySystem` and `TriviaImmersiveManager` for new animations or 3D props. Ensure broadcast messages have a consistent naming pattern (`table_{number}_{action}`).
6. **Testing**: Update `TestDataGeneratorView` and `EnhancedTriviaTestData.swift` to expose new data for QA.
7. **Docs**: Append new operational notes to `FACETIME_SETUP_GUIDE.md`, `USER_GUIDE.md`, or this architecture doc as appropriate.

---

## 14. Quick Reference

| Concern                        | File(s)                                                                                   |
|-------------------------------|-------------------------------------------------------------------------------------------|
| Join logic + listeners        | `Hosted Events/Managers/HostedEventManager.swift`                                         |
| Trivia content + timers       | `Hosted Events/Managers/TriviaGameManager.swift`                                          |
| Host controls UI              | `Hosted Events/Views/HostExperienceView.swift`, `TriviaHostControlsView.swift`           |
| Participant UI                | `Hosted Events/Views/ParticipantExperienceView.swift`                                     |
| Immersive scene management    | `Hosted Events/RealityKit/TriviaImmersiveManager.swift`, `TriviaSpaceView.swift`          |
| FaceTime & audio              | `Hosted Events/Managers/HostAudioManager.swift`, `Views/TableFaceTimeLinkSetupView.swift` |
| Test data + docs              | `Hosted Events/TestData/`, `Hosted Events/TESTING_GUIDE.md`, `USER_GUIDE.md`              |
| SharePlay activity            | `Hosted Events/Activities/TriviaEventActivity.swift`                                      |

---

## 15. Future Improvements (Ideas)

- Formalise a Firestore schema diagram to accompany this doc.
- Extract a generic “live event” protocol so trivia, movies, and other event types can share more infrastructure.
- Add unit/UI tests under `Movie Theater ExperienceTests/` mirroring Hosted Events to cover manager logic and table assignment edge cases.
- Investigate moving FaceTime/SharePlay orchestration into a dedicated service so it can be reused by other features (e.g., Hosted Events → Hosted Concerts).

---

This guide should give you the mental model needed to debug or extend the Hosted Events experience. Pair it with the existing `USER_GUIDE.md` for product behaviour and `TESTING_GUIDE.md` for QA expectations. Happy hosting!
