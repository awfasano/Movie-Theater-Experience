import Foundation
import GroupActivities
import Combine
import RealityKit

@MainActor
class SharePlayManager: ObservableObject {
    static let shared = SharePlayManager()

    // MARK: - Published Properties
    @Published private(set) var participants = Set<Participant>()
    @Published private(set) var localParticipantState: SystemCoordinator.ParticipantState?
    @Published private(set) var isSessionActive = false

    // MARK: - Private Properties
    private var messenger: GroupSessionMessenger?
    
    // This closure will capture the specific session's `leave()` method,
    // solving the generic type issue for cleanup.
    private var leaveCurrentSession: (() -> Void)?

    private var tasks = Set<Task<Void, Never>>()

    // MARK: - Initialization
    private init() {
        // These tasks run in the background, continuously listening for new session invitations.
        Task {
            for await session in DirectCallActivity.sessions() {
                await configureSession(session)
            }
        }
        Task {
            for await session in PublicSpaceActivity.sessions() {
                await configureSession(session)
            }
        }
    }

    // MARK: - Session Configuration
    
    private func configureSession<T: GroupActivity>(_ session: GroupSession<T>) async {
        // 1. Clean up any previous session before starting a new one.
        resetSession()

        // 2. Store a type-erased way to leave the session later.
        leaveCurrentSession = { session.leave() }

        // 3. Get the SystemCoordinator from the session.
        guard let coordinator = await session.systemCoordinator else {
            print("SharePlay Error: Could not get system coordinator from session.")
            return
        }

        // 4. Configure the coordinator for an immersive space experience.
        var config = SystemCoordinator.Configuration()
        config.spatialTemplatePreference = .conversational // Use the simplified API
        config.supportsGroupImmersiveSpace = true // This is required for Full Spaces
        coordinator.configuration = config

        // 5. Set up the messenger for custom data.
        messenger = GroupSessionMessenger(session: session)

        // 6. Mark the session as active and start listening for events.
        isSessionActive = true
        tasks.insert(Task { await listenForSessionEvents(session: session, coordinator: coordinator) })

        // 7. Finally, join the session.
        session.join()
    }

    /// Sets up asynchronous loops to handle all events from an active session.
    private func listenForSessionEvents<T: GroupActivity>(session: GroupSession<T>, coordinator: SystemCoordinator) async {
        // Task to handle participants joining or leaving.
        tasks.insert(Task {
            for await updatedParticipants in session.$activeParticipants.values {
                self.participants = updatedParticipants
                print("SharePlay: Participants changed. Count: \(updatedParticipants.count)")
            }
        })

        // Task to handle updates to the local participant's spatial state.
        tasks.insert(Task {
            for await state in coordinator.localParticipantStates {
                self.localParticipantState = state
                print("SharePlay: Local participant state updated - isSpatial: \(state.isSpatial)")
            }
        })

        // Task to handle incoming custom data messages.
        tasks.insert(Task {
            guard let messenger = self.messenger else { return }
            for await (message, _) in messenger.messages(of: UserPositionUpdate.self) {
                handleIncomingMessage(message)
            }
        })
        
        // Task to handle the session ending for any reason.
        tasks.insert(Task {
            for await state in session.$state.values {
                if case .invalidated = state {
                    print("SharePlay: Session was invalidated.")
                    resetSession()
                }
            }
        })
    }
    
    /// Handles custom messages received from the messenger.
    private func handleIncomingMessage(_ message: UserPositionUpdate) {
        print("SharePlay: Received message - User \(message.userId) moved to seat \(message.newSeatId)")
        NotificationCenter.default.post(name: .userDidMove, object: message)
    }

    // MARK: - Public API for Views
    // These functions remain unchanged as their logic was already correct.

    func startPublicCall(for space: SpaceData) {
        guard let spaceId = space.id else { return }
        let activity = PublicSpaceActivity(spaceId: spaceId, spaceName: space.spaceName)
        Task {
            do { _ = try await activity.activate() }
            catch { print("SharePlay Error: Failed to activate public call: \(error)") }
        }
    }

    func startDirectCall(with remoteUser: SharePlayUser, in space: SpaceData) {
        guard let spaceId = space.id else { return }          // ← only unwrap `space.id`
        let localUserId = AppModel.shared.currentUserId       // ← non-optional
        let localUser   = SharePlayUser(id: localUserId, name: "You")
        
        let activity = DirectCallActivity(spaceId: spaceId,
                                          inviter: localUser,
                                          invitee: remoteUser)
        Task {
            do { _ = try await activity.activate() }
            catch { print("SharePlay Error: Failed to activate direct call: \(error)") }
        }
    }

    func sendMessage<T: Codable>(_ message: T) {
        guard let messenger = messenger else { return }
        Task {
            do { try await messenger.send(message) }
            catch { print("SharePlay Error: Failed to send message: \(error)") }
        }
    }

    func leaveSession() {
        resetSession()
    }

    // MARK: - Private Helpers
    
    /// Resets the manager's state and cancels all running tasks.
    private func resetSession() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        
        leaveCurrentSession?() // Call the stored leave closure.
        leaveCurrentSession = nil

        messenger = nil
        participants.removeAll()
        localParticipantState = nil
        isSessionActive = false
        print("SharePlay: Session reset.")
    }
}

// MARK: - Custom Notification
extension Notification.Name {
    /// Notification posted when a UserPositionUpdate message is received.
    static let userDidMove = Notification.Name("SharePlayUserDidMoveSeat")
}
