import Foundation
import GroupActivities
import Combine
import RealityKit

@MainActor
class SharePlayManager: ObservableObject {
    static let shared = SharePlayManager()

    // MARK: - Published Properties
    // MARK: - CORRECTION: We only need one source of truth for participants.
    // The `Participant` struct itself contains all the necessary state (like pose).
    @Published private(set) var participants = Set<Participant>()
    @Published private(set) var isSessionActive = false
    
    @Published private(set) var localParticipantID: Participant.ID?

    // MARK: - Private Properties
    private var messenger: GroupSessionMessenger?
    private var leaveCurrentSession: (() -> Void)?
    private var tasks = Set<Task<Void, Never>>()

    // MARK: - Initialization
    private init() {
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
        resetSession()
        
        self.localParticipantID = session.localParticipant.id // <-- ADD THIS LINE

        leaveCurrentSession = { session.leave() }

        guard let coordinator = await session.systemCoordinator else {
            print("SharePlay Error: Could not get system coordinator from session.")
            return
        }

        var config = SystemCoordinator.Configuration()
        config.spatialTemplatePreference = .conversational
        config.supportsGroupImmersiveSpace = true
        coordinator.configuration = config

        messenger = GroupSessionMessenger(session: session)
        isSessionActive = true
        tasks.insert(Task { await listenForSessionEvents(session: session) }) // Pass only the session

        session.join()
    }

    /// Sets up asynchronous loops to handle all events from an active session.
    // MARK: - CORRECTION: This function is simplified.
    // We listen to one stream for participants and another for session state.
    private func listenForSessionEvents<T: GroupActivity>(
        session: GroupSession<T>
    ) async {
        // 🔄 Participants
        tasks.insert(Task {
            for await current in session.$activeParticipants.values {   // 〽️ was: session.participants
                await MainActor.run { self.participants = current }
            }
        })

        // 🛑 Session state
        tasks.insert(Task {
            for await state in session.$state.values {
                if case .invalidated = state { resetSession() }
            }
        })
    }
    
    // MARK: - Public API for Views

    func startPublicCall(for space: SpaceData) {
        guard let spaceId = space.id else { return }
        let activity = PublicSpaceActivity(spaceId: spaceId, spaceName: space.spaceName)
        Task {
            do { _ = try await activity.activate() }
            catch { print("SharePlay Error: Failed to activate public call: \(error)") }
        }
    }

    // MARK: - CORRECTION: Fix for "Initializer for conditional binding must have Optional type"
    func startDirectCall(with remoteUser: SharePlayUser, in space: SpaceData) {
        // This guard checks that space.id is not nil.
        guard let spaceId = space.id else { return }
        
        // `currentUserId` is not optional, so we get it directly.
        let localUserId = AppModel.current.currentUserId
        
        // Then we guard to ensure it's not an empty string.
        guard !localUserId.isEmpty else { return }

        let localUser = SharePlayUser(id: localUserId, name: "You") // Replace "You" with a real profile name
        
        let activity = DirectCallActivity(spaceId: spaceId, inviter: localUser, invitee: remoteUser)
        Task {
            do { _ = try await activity.activate() }
            catch { print("SharePlay Error: Failed to activate direct call: \(error)") }
        }
    }

    func leaveSession() {
        resetSession()
    }

    // MARK: - Private Helpers
    private func resetSession() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        localParticipantID = nil // <-- ADD THIS LINE
        leaveCurrentSession?()
        leaveCurrentSession = nil
        messenger = nil
        participants.removeAll()
        isSessionActive = false
        print("SharePlay: Session reset.")
    }
}
