# Movie Theater Experience

**Mission Statement:** This visionOS application provides a shared, immersive movie-watching experience, allowing users to watch videos together in a virtual theater environment, complete with spatial audio and interactive features.

## Table of Contents
- [Core Technologies & Setup](#core-technologies--setup)
- [Project Structure Overview](#project-structure-overview)
- [Dependencies](#dependencies)
- [File-by-File Breakdown](#file-by-file-breakdown)
  - [/Movie Theater Experience](#movie-theater-experience)
  - [/Movie Theater Experience/Initial View](#movie-theater-experienceinitial-view)
  - [/Movie Theater Experience/Immersive](#movie-theater-experienceimmersive)
  - [/Movie Theater Experience/Chat](#movie-theater-experiencechat)
  - [/Movie Theater Experience/Model](#movie-theater-experiencemodel)
  - [/Movie Theater Experience/Config](#movie-theater-experienceconfig)
  - [/Movie Theater Experience/Calendar](#movie-theater-experiencecalendar)
  - [/Movie Theater Experience/Core](#movie-theater-experiencecore)
  - [/Movie Theater Experience/Movie Picker](#movie-theater-experiencemovie-picker)
  - [/Movie Theater Experience/Utilities](#movie-theater-experienceutilities)
- [Assets](#assets)
- [Testing](#testing)


## Core Technologies & Setup

### Technology Stack
- **Swift:** The primary programming language.
- **SwiftUI:** Used for building the user interface.
- **RealityKit:** Used for creating immersive 3D experiences.
- **visionOS:** The target operating system.
- **Firebase:** Used for backend services, including Analytics, Auth, and Firestore.
- **CocoaPods & Swift Package Manager:** Used for managing external and local dependencies.

### Setup and Installation
1.  Clone the repository.
2.  Install CocoaPods dependencies: `pod install`
3.  Open `Movie Theater Experience.xcworkspace` in Xcode.
4.  Select a target simulator or a connected Apple Vision Pro device.
5.  Build and run the project (Cmd+R).

## Project Structure Overview

/Movie Theater Experience copy/
├── /Movie Theater Experience/          # Main application source code
│   ├── /Assets.xcassets # Image and color assets
│   ├── /Calendar        # Calendar and event-related views
│   ├── /Chat            # Components for the chat functionality
│   ├── /Config          # Configuration and manager classes
│   ├── /Core            # Core application logic and entry point
│   ├── /Immersive       # Code for the immersive video experience
│   ├── /Initial View    # Initial views presented to the user
│   ├── /Model           # Data models for the application
│   ├── /Movie Picker    # UI for picking video files
│   ├── /Preview Content # Assets for Xcode Previews
│   ├── /Sign Up         # Views related to user sign-up
│   └── /Utilities       # Utility extensions and helper functions
├── /Movie Theater Experience.xcodeproj/ # Xcode project configuration
├── /Packages/           # Swift Package Manager dependencies
└── /Pods/               # CocoaPods dependencies

## Dependencies

### CocoaPods
- **FirebaseAnalytics:** Used for gathering analytics data.
- **FirebaseAuth:** Used for user authentication.
- **FirebaseCore:** Core Firebase library.
- **FirebaseFirestore:** Used as the primary database for the application.

### Swift Package Manager
- **RealityKitContent:** A local package containing RealityKit content for the main application.
- **floatingHouse:** A local package containing the "floating house" RealityKit scene.

## File-by-File Breakdown

### /Movie Theater Experience

#### Movie_Theater_ExperienceApp.swift
- **Purpose:** This is the main entry point for the application. It defines the app's structure, manages the main state objects (`AppModel`, `ImmersiveSpaceManager`, `SharedSpaceSeatSelection`), and sets up the different window groups and immersive spaces.
- **Dependencies:** SwiftUI, `AppModel`, `ImmersiveSpaceManager`, `SharedSpaceSeatSelection`, `ContentView`, `VolumetricSpaceView`, `SpacesView`, `ImmersiveView`.
- **Struct: `Movie_Theater_ExperienceApp`**
    - **Description:** The entry point of the visionOS application, conforming to the `App` protocol. It sets up the application's scene hierarchy, including `WindowGroup`s for 2D content and `ImmersiveSpace`s for 3D experiences. It also initializes and manages key shared state objects and managers.
    - **Key Responsibilities:**
        - Initializing Firebase via `AppDelegate`.
        - Declaring and managing the application's main `AppModel` and other global state objects.
        - Defining the various windows and immersive spaces available in the application.
        - Passing environment objects to child views.
        - Handling scene phase changes (e.g., app entering background).
    - **Properties:**
        - `delegate`: An instance of `AppDelegate` for Firebase initialization.
        - `appModel`: The main `AppModel` instance, holding global application state.
        - `immersiveSpaceManager`: Manages the lifecycle of immersive spaces.
        - `sharedSpaceSeatSelection`: Manages seat selection in shared spaces.
        - `theatreEntityWrapper`: Manages the main theatre 3D entity.
        - `windowManager`: Tracks the open/closed state of application windows.
        - `spacesEntityWrapper`: Manages 3D entities for general spaces.
        - `audioLoader`: Loads spatial audio.
        - `firebaseEventManager`: Manages Firebase events.
        - `emojiManager`: Manages emoji interactions.
        - `spacesChatManager`: Manages chat for spaces.
        - `sharePlayManager`: Manages SharePlay activities.
    - **Methods:**
        - `body`: The main scene builder, defining `WindowGroup`s and `ImmersiveSpace`s.
        - `openSpaceList()`: A helper function to open the space list window.

#### AppModel.swift
- **Purpose:** A simple observable object that holds shared application state, specifically the `selectedSpace`.
- **Dependencies:** SwiftUI.
- **Class: `AppModel`**
    - **Description:** A central observable class that manages the application's global state. It acts as a single source of truth for data that needs to be shared across different views and components, such as the currently selected video, event details, and the state of immersive spaces.
    - **Key Responsibilities:**
        - Holding and updating application-wide data.
        - Providing access to shared resources and managers.
        - Managing the lifecycle and transitions between different immersive spaces.
        - Initializing and persisting the user's unique ID.
    - **Properties:**
        - `shared`: The singleton instance of `AppModel`.
        - `immersiveSpaceID`: Identifier for the main immersive space.
        - `spacesID`: Identifier for the spaces immersive space.
        - `selectedVideoURL`: The URL of the video selected for playback.
        - `currentEvent`: The currently selected `CalendarEvent`.
        - `isMovieWindowOpen`: A boolean indicating if the 2D movie window is open.
        - `lastKnownPlaybackTime`: The last known playback time of the video.
        - `wasPlayingOnSwitch`: A flag indicating if the video was playing before a view switch.
        - `currentActiveSpace`: The identifier of the currently active immersive space.
        - `currentUserId`: The unique identifier for the current user.
        - `resumePlaybackAfterTransition`: A flag to resume playback after a transition.
        - `windowToOpen`: A request to open a specific window with optional data.
        - `selectedSpace`: The currently selected `SpaceData` object.
    - **Methods:**
        - `init()`: Initializes the `AppModel`.
        - `updateSelectedSpaceSeat(to:)`: Updates the selected seat within the `selectedSpace`.
        - `initializeUserId(from:appStorage:)`: Initializes the user ID, either from `AppStorage` or by generating a new one.
        - `cleanupImmersiveSpace()`: Initiates cleanup of the immersive space.
        - `switchToSpace(_:)`: Handles the logic for switching between different immersive spaces.
        - `requestWindowOpen(id:value:)`: Requests the opening of a specific window.
        - `resetAppState()`: Resets various application states.
        - `immersiveSpaceWillOpen()`: Callback when an immersive space is about to open.
        - `immersiveSpaceDidOpen()`: Callback when an immersive space has opened.
        - `immersiveSpaceWillClose()`: Callback when an immersive space is about to close.
        - `immersiveSpaceDidClose()`: Callback when an immersive space has closed.
        - `immersiveSpaceDidFailToOpen()`: Callback when an immersive space fails to open.
        - `handleEventSelection(_:)`: Prepares the `AppModel` for an event selection.

#### Initial View/ContentView.swift
- **Purpose:** This file defines the initial view that is presented when the app launches. It currently contains the `TabBarWindow`.
- **Dependencies:** SwiftUI, `TabBarWindow`.

### /Movie Theater Experience/Initial View

#### SpacesView.swift
- **Purpose:** This view allows users to select a virtual space. It presents a list of available spaces and, upon selection, either transitions to the immersive experience or opens a seat selection view.
- **Dependencies:** SwiftUI, RealityKit, `AppModel`, `ImmersiveSpaceManager`, `SharedSpaceSeatSelection`, `SpaceDetailView`, `SpaceListView`, `SeatSelectionWindow`.

#### SharePlay/ShareplayManager.swift
- **Purpose:** Manages the SharePlay functionality, enabling users to join and participate in shared experiences. It handles session creation, participant management, and communication between users.
- **Dependencies:** GroupActivities, Combine, RealityKit.

#### TTS Storyteller/StoryTellerAudioService.swift
- **Purpose:** This service manages the playback of audio narration and provides real-time audio analysis, including the overall level (RMS) and a 128-bucket frequency spectrum. It uses `MTAudioProcessingTap` to process the audio from an `AVPlayer`.
- **Dependencies:** AVFoundation, Accelerate, CoreMedia, os.lock.

#### Audio/AudioPositionSynchronizer.swift
- **Purpose:** A helper class that synchronizes the audio playback parameters (volume, pan) of an `AVAudioPlayer` with the position of a RealityKit entity in 3D space. This is crucial for creating a believable spatial audio experience.
- **Dependencies:** RealityKit, AVFAudio.

#### Map/SeatOrbEntities.swift
- **Purpose:** Defines the visual representation of a single seat in the `SpaceMapView`. It's a `RealityView` that shows a sphere (orb) which changes appearance based on its state (available, selected, unavailable) and has a halo effect.
- **Dependencies:** SwiftUI, RealityKit.

#### Space Tab/FlowLayout.swift
- **Purpose:** A custom SwiftUI `Layout` that arranges subviews in a flowing, tag-cloud-like manner. It's used to display tags associated with a space.
- **Dependencies:** SwiftUI.

#### Space Tab/SpaceDetailView.swift
- **Purpose:** This view displays detailed information about a selected `SpaceData` object, including a volumetric preview, name, description, tags, and a link to the original 3D model.
- **Dependencies:** SwiftUI, `VolumetricSpaceView`, `FlowLayout`.

#### Volume/VolumetricSpaceModel.swift
- **Purpose:** The view model responsible for loading and managing the 3D content of a `SpaceData` object for preview in the `VolumetricSpaceView`. It handles loading the USDZ file, processing the entity for display, and managing loading/error states.
- **Dependencies:** RealityKit, Combine, SwiftUI.

#### Intro Volume/OccupancyView.swift
- **Purpose:** A view that displays the current and maximum occupancy of a space, along with a progress bar that changes color based on how full the space is.
- **Dependencies:** SwiftUI, `OccupancyProgressView`.

#### Intro Volume/SpaceRowView.swift
- **Purpose:** A view that displays a single row in a list of available spaces, showing the space's name and current occupancy.
- **Dependencies:** SwiftUI.

### /Movie Theater Experience/Immersive

#### ImmersiveView.swift
- **Purpose:** This is the core view for the immersive movie-watching experience. It sets up the RealityKit scene, manages the theatre environment, and coordinates the various managers (`VideoPlayerManager`, `TheatreLightingManager`, `SpatialAudioManager`, etc.) to create the final experience.
- **Dependencies:** SwiftUI, RealityKit, AVFoundation, Combine, `AppModel`, `WindowManager`, `SharedSeatSelection`, `TheatreEntityWrapper`, `ImmersiveSpaceManager`, `VideoSyncService`, `VideoPlayerManager`, `TheatreLightingManager`, `SpatialAudioManager`.
- **Struct: `ImmersiveView`**
    - **Description:** The main SwiftUI view for the immersive experience. It uses a `RealityView` to render the 3D scene and manages the lifecycle of the various components involved in the experience.
    - **Key Responsibilities:**
        - Setting up the initial RealityKit scene and theatre environment.
        - Coordinating the `VideoPlayerManager`, `VideoSyncService`, `TheatreLightingManager`, and `SpatialAudioManager`.
        - Handling user interactions and state changes within the immersive space.
        - Managing the presentation of the end screen and other UI elements.
- **Methods:**
    - `setupTheatreEnvironment(in:)`: Loads the 3D model of the theatre, configures the lighting and audio, and adds the scene to the `RealityView`.
    - `configureScreenEntities(in:)`: Finds the screen entity in the 3D model and prepares it for video playback.
    - `handleMovieWindowChange(_:)`: Handles the opening and closing of the 2D movie window, showing or hiding the immersive video screen accordingly.
    - `configureVideoWithSync(screenEntity:url:)`: Configures the video player and synchronization service for a given video URL.
    - `adjustViewerPosition(for:)`: Adjusts the viewer's position in the scene based on the selected seat.

#### ImmersiveSpaceManager.swift
- **Purpose:** A singleton manager that controls the lifecycle of the immersive space. It handles opening, closing, and cleaning up the immersive environment, and provides a centralized way to manage the state of the immersive experience.
- **Dependencies:** SwiftUI, RealityKit.

#### VideoPlayerManager.swift
- **Purpose:** Manages the `AVPlayer` instance used for video playback. It configures the video for display in RealityKit, handles player state changes, and communicates with the `VideoSyncService` to keep playback synchronized.
- **Dependencies:** SwiftUI, RealityKit, AVFoundation, Combine, `TheatreEntityWrapper`, `VideoSyncService`, `TheatreLightingManager`, `SpatialAudioManager`.

#### VideoSyncService.swift
- **Purpose:** This service synchronizes video playback across multiple devices using Firebase. It manages the shared playback state (playing, paused, position), handles host election, and ensures that all participants have a consistent viewing experience.
- **Dependencies:** Foundation, Firebase, AVFoundation, Observation.

- **Class: `VideoSyncService`**
    - **Description:** A singleton service responsible for synchronizing video playback across multiple devices in a shared experience. It uses Firebase Firestore as a backend to manage and distribute the playback state, including play/pause status, current playback time, and host election.
    - **Key Responsibilities:**
        - Managing the connection to Firebase.
        - Handling host election to ensure a single source of truth for playback.
        - Listening for and applying playback state changes from the host.
        - Updating the playback state in Firebase (if host).
        - Managing user presence within a session.
        - Handling cleanup of resources when a session ends.
- **Enums:**
    - `VideoSyncError`: Defines custom errors for the service.
    - `CleanupLevel`: Specifies the level of cleanup to perform.
    - `ViewState`: Represents the current view state (immersive, windowed, etc.).
- **Structs:**
    - `SyncSnapshot`: A snapshot of the playback state.
- **Properties:**
    - `shared`: The singleton instance.
    - `isHost`: A boolean indicating if the current user is the host.
    - `isPlaying`: A boolean indicating if the video is currently playing.
    - `currentTime`: The current playback time.
    - `currentPlayer`: The `AVPlayer` instance being managed.
- **Methods:**
    - `configureSync(eventId:userId:event:)`: Configures the service for a specific event.
    - `startSync(with:)`: Starts the synchronization process with a given `AVPlayer`.
    - `handlePlayPause(isPlaying:)`: Handles play/pause actions.
    - `handleSeek(to:)`: Handles seeking to a specific time.
    - `cleanup(level:)`: Cleans up resources based on the specified level.

#### TheatreEntities/SpatialAudioManager.swift
- **Purpose:** Manages the spatial audio for the immersive experience. It discovers speaker entities in the 3D model, sets up the `AVAudioEngine`, and configures the audio environment to create a realistic 3D soundscape.
- **Dependencies:** AVFoundation, RealityKit.

#### TheatreEntities/TheatreEntityWrapper.swift
- **Purpose:** A singleton that holds and manages the main theatre `Entity`. It provides a centralized point of access to the theatre model and its sub-entities (like the screen and emoji emitters), and handles cleanup of these resources.
- **Dependencies:** SwiftUI, RealityKit.

#### TheatreEntities/TheatreLightManager.swift
- **Purpose:** Manages the lighting effects within the theatre environment, including the projector light beam, dust particles, and flicker effects, to enhance the cinematic feel.
- **Dependencies:** SwiftUI, RealityKit.

#### TheatreEntities/TheatreVisibilityManager.swift
- **Purpose:** A simple observable object that manages the visibility of the theatre model.
- **Dependencies:** Foundation.

### /Movie Theater Experience/Chat

#### ChatView.swift
- **Purpose:** This view provides the user interface for the chat window. It displays a list of messages and includes a text input area for sending new messages.
- **Dependencies:** SwiftUI, FirebaseFirestore, `ChatViewModel`, `ChatScrollView`, `CustomTextInputView`.

#### ChatViewModel.swift
- **Purpose:** The view model for the `ChatView`. It fetches and manages the chat messages from Firebase, handles sending new messages, and provides the data needed by the view.
- **Dependencies:** SwiftUI, Firebase, Combine, `EventManagerProtocol`.

#### Emoji/EmojiButtonView.swift
- **Purpose:** A view that displays a row of emoji buttons. Tapping a button sends an emoji reaction to the current event or space.
- **Dependencies:** SwiftUI, FirebaseFirestore, `EmojiManager`.

#### Emoji/EmojiManager.swift
- **Purpose:** A singleton manager for handling emoji reactions. It processes emoji taps, sends the data to Firebase, and triggers visual effects in the immersive view.
- **Dependencies:** Foundation, FirebaseFirestore, `TheatreEntityWrapper`.

#### CustomTextInput.swift
- **Purpose:** A `UIViewRepresentable` that wraps a `UITextView` to create a custom, multi-line text input field with dynamic height and placeholder text.
- **Dependencies:** SwiftUI, UIKit.

#### Emitters.swift
- **Purpose:** Defines the data model for an emoji emission event.
- **Dependencies:** Foundation.

#### ExpandingTextView.swift
- **Purpose:** A SwiftUI view that provides an expanding text field for message input.
- **Dependencies:** SwiftUI, RealityKit.

#### WindowManager.swift
- **Purpose:** A simple observable object that tracks the open/closed state of various windows in the application.
- **Dependencies:** SwiftUI.

### /Movie Theater Experience/Model

#### CalendarEvent.swift
- **Purpose:** Defines the data model for a calendar event, including its properties and a `CalendarService` class for fetching event data from Firebase.
- **Dependencies:** Foundation, SwiftUI, RealityKit, FirebaseFirestore.

#### EventView.swift
- **Purpose:** This view displays a single calendar event with its title, time, and description. It also handles user interaction for joining an event and entering the immersive space.
- **Dependencies:** SwiftUI, RealityKit, `AppModel`, `ImmersiveSpaceManager`, `TheatreEntityWrapper`, `SharedSeatSelection`.

#### FirestoreManager.swift
- **Purpose:** A manager class for handling interactions with multiple Firestore databases.
- **Dependencies:** Foundation, FirebaseFirestore, Combine.

### /Movie Theater Experience/Config

#### EventManagerConfiguration.swift
- **Purpose:** A configuration struct that defines the root collection in Firestore for the `FirebaseEventManager`.
- **Dependencies:** Foundation, Firebase.

#### EventManagerProtocol.swift
- **Purpose:** A protocol that defines the interface for an event manager, abstracting the underlying implementation (e.g., Firebase).
- **Dependencies:** Foundation.

#### FirebaseEventManager.swift
- **Purpose:** An implementation of the `EventManagerProtocol` that uses Firebase to manage chat messages and emoji reactions for events.
- **Dependencies:** Foundation, FirebaseFirestore, Combine.

#### SpacesChatManager.swift
- **Purpose:** A service for handling chat and emoji functionality specifically for Spaces, using a separate Firebase database.
- **Dependencies:** Foundation, FirebaseFirestore, Combine.

### /Movie Theater Experience/Calendar

#### CalendarView.swift
- **Purpose:** The main view for the calendar. It displays a monthly calendar, a daily timeline of events, and allows the user to navigate between dates.
- **Dependencies:** SwiftUI, RealityKit, `AppModel`, `CalendarService`.

#### CurrentTimeLineView.swift
- **Purpose:** A view that displays a vertical line on the timeline to indicate the current time.
- **Dependencies:** Foundation, SwiftUI, RealityKit.

#### DaySelectionView.swift
- **Purpose:** A view that displays a horizontal list of days in the current month, allowing the user to select a specific day.
- **Dependencies:** Foundation, SwiftUI, RealityKit.

#### PositionedEvents.swift
- **Purpose:** This file is currently empty.

#### TimeLineline.swift
- **Purpose:** Defines a `Shape` for drawing a vertical line in the timeline view.
- **Dependencies:** Foundation, SwiftUI, RealityKit.

#### TimelineView.swift
- **Purpose:** This view displays the timeline of events for a selected day. It handles the layout and positioning of events, as well as the current time indicator.
- **Dependencies:** SwiftUI, RealityKit, `AppModel`, `CalendarService`, `ImmersiveSpaceManager`.

#### TopNavigationView.swift
- **Purpose:** A view that provides the top navigation bar for the calendar, including month navigation and a refresh button.
- **Dependencies:** Foundation, SwiftUI.

### /Movie Theater Experience/Core

#### AppModel.swift
- **Purpose:** The main observable object that holds the shared state for the entire application. It manages the selected video, the current event, the state of the immersive space, and the user's ID.
- **Dependencies:** SwiftUI, RealityKit, AVFoundation.
- **Class: `AppModel`**
    - **Description:** A central observable class that manages the application's global state. It acts as a single source of truth for data that needs to be shared across different views and components, such as the currently selected video, event details, and the state of immersive spaces.
    - **Key Responsibilities:**
        - Holding and updating application-wide data.
        - Providing access to shared resources and managers.
        - Managing the lifecycle and transitions between different immersive spaces.
        - Initializing and persisting the user's unique ID.
    - **Properties:**
        - `shared`: The singleton instance of `AppModel`.
        - `immersiveSpaceID`: Identifier for the main immersive space.
        - `spacesID`: Identifier for the spaces immersive space.
        - `selectedVideoURL`: The URL of the video selected for playback.
        - `currentEvent`: The currently selected `CalendarEvent`.
        - `isMovieWindowOpen`: A boolean indicating if the 2D movie window is open.
        - `lastKnownPlaybackTime`: The last known playback time of the video.
        - `wasPlayingOnSwitch`: A flag indicating if the video was playing before a view switch.
        - `currentActiveSpace`: The identifier of the currently active immersive space.
        - `currentUserId`: The unique identifier for the current user.
        - `resumePlaybackAfterTransition`: A flag to resume playback after a transition.
        - `windowToOpen`: A request to open a specific window with optional data.
        - `selectedSpace`: The currently selected `SpaceData` object.
    - **Methods:**
        - `init()`: Initializes the `AppModel`.
        - `updateSelectedSpaceSeat(to:)`: Updates the selected seat within the `selectedSpace`.
        - `initializeUserId(from:appStorage:)`: Initializes the user ID, either from `AppStorage` or by generating a new one.
        - `cleanupImmersiveSpace()`: Initiates cleanup of the immersive space.
        - `switchToSpace(_:)`: Handles the logic for switching between different immersive spaces.
        - `requestWindowOpen(id:value:)`: Requests the opening of a specific window.
        - `resetAppState()`: Resets various application states.
        - `immersiveSpaceWillOpen()`: Callback when an immersive space is about to open.
        - `immersiveSpaceDidOpen()`: Callback when an immersive space has opened.
        - `immersiveSpaceWillClose()`: Callback when an immersive space is about to close.
        - `immersiveSpaceDidClose()`: Callback when an immersive space has closed.
        - `immersiveSpaceDidFailToOpen()`: Callback when an immersive space fails to open.
        - `handleEventSelection(_:)`: Prepares the `AppModel` for an event selection.

#### Movie_Theater_ExperienceApp.swift
- **Purpose:** The main entry point for the application. It sets up the Firebase app delegate, initializes the main `AppModel` and other managers, and defines the window groups and immersive spaces that make up the app.
- **Dependencies:** SwiftUI, FirebaseCore, `AppModel`, `ImmersiveSpaceManager`, `SharedSeatSelection`, `TheatreEntityWrapper`, `WindowManager`, `SpacesEntityWrapper`, `SpatialAudioLoader`, `FirebaseEventManager`, `EmojiManager`, `SpacesChatManager`, `SharePlayManager`.
- **Struct: `Movie_Theater_ExperienceApp`**
    - **Description:** The entry point of the visionOS application, conforming to the `App` protocol. It sets up the application's scene hierarchy, including `WindowGroup`s for 2D content and `ImmersiveSpace`s for 3D experiences. It also initializes and manages key shared state objects and managers.
    - **Key Responsibilities:**
        - Initializing Firebase via `AppDelegate`.
        - Declaring and managing the application's main `AppModel` and other global state objects.
        - Defining the various windows and immersive spaces available in the application.
        - Passing environment objects to child views.
        - Handling scene phase changes (e.g., app entering background).
    - **Properties:**
        - `delegate`: An instance of `AppDelegate` for Firebase initialization.
        - `appModel`: The main `AppModel` instance, holding global application state.
        - `immersiveSpaceManager`: Manages the lifecycle of immersive spaces.
        - `sharedSpaceSeatSelection`: Manages seat selection in shared spaces.
        - `theatreEntityWrapper`: Manages the main theatre 3D entity.
        - `windowManager`: Tracks the open/closed state of application windows.
        - `spacesEntityWrapper`: Manages 3D entities for general spaces.
        - `audioLoader`: Loads spatial audio.
        - `firebaseEventManager`: Manages Firebase events.
        - `emojiManager`: Manages emoji interactions.
        - `spacesChatManager`: Manages chat for spaces.
        - `sharePlayManager`: Manages SharePlay activities.
    - **Methods:**
        - `body`: The main scene builder, defining `WindowGroup`s and `ImmersiveSpace`s.
        - `openSpaceList()`: A helper function to open the space list window.

#### ToggleImmersiveSpaceButton.swift
- **Purpose:** A simple button that toggles the immersive space on and off.
- **Dependencies:** SwiftUI, `AppModel`, `ImmersiveSpaceManager`, `VideoSyncService`.
- **Struct: `ToggleImmersiveSpaceButton`**
    - **Description:** A SwiftUI `View` that provides a button to toggle the immersive space. It interacts with `ImmersiveSpaceManager` and `VideoSyncService` to handle the opening, closing, and cleanup of the immersive environment, and to manage video playback state during transitions.
    - **Key Responsibilities:**
        - Providing a user interface element to control immersive space visibility.
        - Initiating the dismissal or opening of the immersive space.
        - Handling cleanup of video synchronization and player resources when the immersive space is dismissed.
        - Optionally opening a 2D movie window if the immersive space is hidden and a video is selected.
    - **Properties:**
        - `appModel`: The application's shared data model.
        - `dismissImmersiveSpace`: Environment action to dismiss the immersive space.
        - `openImmersiveSpace`: Environment action to open the immersive space.
        - `openWindow`: Environment action to open a new window.
        - `spaceManager`: The shared instance of `ImmersiveSpaceManager`.
        - `videoSyncService`: The shared instance of `VideoSyncService`.
    - **Methods:**
        - `body`: The view's content, defining the button's appearance and action.
        - `handleImmersiveSpaceDismissal()`: Handles the logic for dismissing the immersive space, including cleanup.
        - `handleImmersiveSpaceOpening()`: Handles the logic for opening the immersive space.

#### VolumetricSpaceWrapper.swift
- **Purpose:** A wrapper view that sets up the environment for the `VolumetricSpaceView`.
- **Dependencies:** SwiftUI, `AppModel`, `SelectedSpace`, `VolumetricSpaceView`.
- **Struct: `VolumetricSpaceWrapper`**
    - **Description:** A SwiftUI `View` that acts as a wrapper to set up the necessary environment objects for the `VolumetricSpaceView`. It ensures that the `VolumetricSpaceView` receives the correct `AppModel` and a local `SelectedSpace` instance, which is crucial for displaying the 3D content of a selected space.
    - **Key Responsibilities:**
        - Providing the `AppModel` to the `VolumetricSpaceView`'s environment.
        - Creating and providing a `SelectedSpace` instance to the `VolumetricSpaceView`'s environment.
    - **Properties:**
        - `space`: The `SpaceData` object to be displayed in the `VolumetricSpaceView`.
        - `appModel`: The application's shared data model (injected via `@Environment`).
    - **Methods:**
        - `body`: The view's content, setting up the environment for `VolumetricSpaceView`.

### /Movie Theater Experience/Movie Picker

#### VideoPicker.swift
- **Purpose:** This file is currently empty.

### /Movie Theater Experience/Utilities

#### Extensions.swift
- **Purpose:** This file contains various extensions to standard Swift types like `Color`, `float4x4`, and `Date`, providing helper methods and computed properties.
- **Dependencies:** Foundation, SwiftUI, UIKit.
- **Extensions:**
    - **`Color` Extension:**
        - **Purpose:** Provides custom color definitions and utility initializers/properties for converting between `Color` and hex strings.
        - **Properties:**
            - `accentColor`, `accentColor2`, `incomingBubble`, `outgoingBubble`: Predefined static `Color` instances for consistent styling.
            - `init?(hex: String)`: Initializes a `Color` from a hexadecimal string (e.g., "#RRGGBB" or "RRGGBB").
            - `var toHex: String?`: Converts the `Color` instance to its hexadecimal string representation.
    - **`float4x4` Extension:**
        - **Purpose:** Provides a convenience initializer for creating a `float4x4` transformation matrix that represents a "look at" orientation, useful for camera or object positioning in 3D space.
        - **Methods:**
            - `init(lookAt:target:up:)`: Creates a transformation matrix that makes an object at `from` look towards `target`, with `up` defining the upward direction.
    - **`Date` Extension:**
        - **Purpose:** Adds various convenience properties and methods for date manipulation and formatting.
        - **Properties:**
            - `startOfMonth`: Returns the first day of the month for the given date.
            - `monthAndYear`: Returns a formatted string of the month and year (e.g., "January 2024").
            - `weekdaySymbol`: Returns a short string representation of the weekday (e.g., "Mon", "Tue").
            - `day`: Returns the day of the month as an integer.
            - `hourAndMinute`: Returns a formatted string of the hour and minute (e.g., "14:30").
        - **Methods:**
            - `daysInMonth()`: Returns an array of `Date` objects for each day in the month of the receiver.
    - **`View` Extension (Conditional on UIKit):**
        - **Purpose:** Provides a utility method to hide the software keyboard.
        - **Methods:**
            - `hideKeyboard()`: Dismisses the active software keyboard.

## Assets

### /Movie Theater Experience/Assets.xcassets
- **Purpose:** This is the main asset catalog for the application. It contains all the images, colors, and other assets used in the user interface.

### /Movie Theater Experience/Preview Content/Preview Assets.xcassets
- **Purpose:** This asset catalog contains assets used specifically for Xcode Previews.

### 3D Models
- **Movie Theatre One.usdz:** The main 3D model for the movie theater environment.
- **Scene.usdz:** A general-purpose 3D scene file.
- **Packages/MovieTheatre.usdz:** A 3D model of the movie theatre, likely used as a Swift package.
- **Packages/Scene.usdz:** A general-purpose 3D scene file, likely used as a Swift package.

## Testing

### /Movie Theater ExperienceTests/
- **Purpose:** This directory contains the unit tests for the application. The tests cover various components, including the `AppModel`, `CalendarService`, `ChatViewModel`, and more. The tests are crucial for ensuring the stability and correctness of the application's logic.



cell phone tower

boolean, we don't care about each billion
aggregate
by state
county
too much data
