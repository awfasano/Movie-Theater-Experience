import Foundation
import GroupActivities
import Combine
import AVFoundation

// MARK: - SharePlay Activity Types
struct PublicSpaceActivity: GroupActivity {
    static let activityIdentifier = "com.yourcompany.yourapp.PublicSpaceActivity"
    
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Join Public Space"
        metadata.type = .generic
        metadata.supportsContinuationOnTV = false
        return metadata
    }
}

struct DirectCallActivity: GroupActivity {
    static let activityIdentifier = "com.yourcompany.yourapp.DirectCallActivity"
    
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Direct Call"
        metadata.type = .generic
        metadata.supportsContinuationOnTV = false
        return metadata
    }
}

// MARK: - Participant Model
struct Participant: Identifiable, Hashable {
    let id: UUID
    let name: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Participant, rhs: Participant) -> Bool {
        lhs.id == rhs.id
    }
}

// Create a typealias to distinguish from GroupActivities.Participant
typealias SharePlayParticipant = Participant

// MARK: - SharePlayManager
@MainActor
class SharePlayManager: ObservableObject {
    static let shared = SharePlayManager()
    
    // MARK: - Published Properties
    @Published var isSessionActive: Bool = false
    @Published var participants: Set<SharePlayParticipant> = []
    @Published var localParticipantID: UUID?
    
    // MARK: - Private Properties
    private var publicSpaceSession: GroupSession<PublicSpaceActivity>?
    private var directCallSession: GroupSession<DirectCallActivity>?
    private var cancellables = Set<AnyCancellable>()
    private var sessionCancellables = Set<AnyCancellable>()
    
    private init() {
        configureAudioSession()
        setupSessionObservers()
    }
    
    // MARK: - Public Methods
    func startPublicSpaceActivity() async throws {
        let activity = PublicSpaceActivity()
        
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            do {
                _ = try await activity.activate()
                print("SharePlay: Public space activity activated successfully")
            } catch {
                print("SharePlay: Failed to activate public space activity: \(error)")
                throw error
            }
        case .activationDisabled:
            print("SharePlay: Activation is disabled")
        case .cancelled:
            print("SharePlay: Activation was cancelled")
        @unknown default:
            print("SharePlay: Unknown activation result")
        }
    }
    
    func startDirectCallActivity() async throws {
        let activity = DirectCallActivity()
        
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            do {
                _ = try await activity.activate()
                print("SharePlay: Direct call activity activated successfully")
            } catch {
                print("SharePlay: Failed to activate direct call activity: \(error)")
                throw error
            }
        case .activationDisabled:
            print("SharePlay: Activation is disabled")
        case .cancelled:
            print("SharePlay: Activation was cancelled")
        @unknown default:
            print("SharePlay: Unknown activation result")
        }
    }
    
    func leaveSession() {
        publicSpaceSession?.leave()
        directCallSession?.leave()
        cleanupSession()
    }
    
    // MARK: - Private Methods
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
        } catch {
            print("SharePlay: Failed to configure audio session: \(error)")
        }
    }
    
    private func setupSessionObservers() {
        // Observe public space sessions using Task
        Task {
            for await session in PublicSpaceActivity.sessions() {
                configurePublicSpaceSession(session)
            }
        }
        
        // Observe direct call sessions using Task
        Task {
            for await session in DirectCallActivity.sessions() {
                configureDirectCallSession(session)
            }
        }
    }
    
    private func configurePublicSpaceSession(_ session: GroupSession<PublicSpaceActivity>) {
        // Clean up any existing session
        publicSpaceSession?.leave()
        sessionCancellables.removeAll()
        
        publicSpaceSession = session
        
        // Update session state
        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handlePublicSpaceSessionStateChange(state)
            }
            .store(in: &sessionCancellables)
        
        // Update participants
        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                self?.updatePublicSpaceParticipants(participants)
            }
            .store(in: &sessionCancellables)
        
        // Join the session
        session.join()
        
        print("SharePlay: Configured public space session with \(session.activeParticipants.count) participants")
    }
    
    private func configureDirectCallSession(_ session: GroupSession<DirectCallActivity>) {
        // Clean up any existing session
        directCallSession?.leave()
        sessionCancellables.removeAll()
        
        directCallSession = session
        
        // Update session state
        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleDirectCallSessionStateChange(state)
            }
            .store(in: &sessionCancellables)
        
        // Update participants
        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                self?.updateDirectCallParticipants(participants)
            }
            .store(in: &sessionCancellables)
        
        // Join the session
        session.join()
        
        print("SharePlay: Configured direct call session with \(session.activeParticipants.count) participants")
    }
    
    private func handlePublicSpaceSessionStateChange(_ state: GroupSession<PublicSpaceActivity>.State) {
        switch state {
        case .waiting:
            print("SharePlay: Public space session is waiting")
            isSessionActive = false
        case .joined:
            print("SharePlay: Public space session joined successfully")
            isSessionActive = true
        case .invalidated(let reason):
            print("SharePlay: Public space session invalidated: \(reason)")
            isSessionActive = false
            cleanupSession()
        @unknown default:
            print("SharePlay: Unknown public space session state")
        }
    }
    
    private func handleDirectCallSessionStateChange(_ state: GroupSession<DirectCallActivity>.State) {
        switch state {
        case .waiting:
            print("SharePlay: Direct call session is waiting")
            isSessionActive = false
        case .joined:
            print("SharePlay: Direct call session joined successfully")
            isSessionActive = true
        case .invalidated(let reason):
            print("SharePlay: Direct call session invalidated: \(reason)")
            isSessionActive = false
            cleanupSession()
        @unknown default:
            print("SharePlay: Unknown direct call session state")
        }
    }
    
    private func updatePublicSpaceParticipants(_ groupParticipants: Set<GroupActivities.Participant>) {
        updateParticipants(groupParticipants)
    }
    
    private func updateDirectCallParticipants(_ groupParticipants: Set<GroupActivities.Participant>) {
        updateParticipants(groupParticipants)
    }
    
    private func updateParticipants(_ groupParticipants: Set<GroupActivities.Participant>) {
        // Convert GroupActivities.Participant to our custom Participant type
        let convertedParticipants = Set(groupParticipants.map { groupParticipant in
            SharePlayParticipant(id: groupParticipant.id, name: nil) // GroupActivities.Participant doesn't expose name
        })
        
        self.participants = convertedParticipants
        
        // Set local participant ID if not already set
        if localParticipantID == nil, let firstParticipant = convertedParticipants.first {
            localParticipantID = firstParticipant.id
        }
        
        print("SharePlay: Updated participants count: \(convertedParticipants.count)")
    }
    
    private func cleanupSession() {
        sessionCancellables.removeAll()
        publicSpaceSession = nil
        directCallSession = nil
        isSessionActive = false
        participants.removeAll()
        localParticipantID = nil
        
        print("SharePlay: Session cleaned up")
    }
}

// MARK: - SystemCoordinator (Placeholder for spatial tracking)
@MainActor
class SystemCoordinator: ObservableObject {
    struct ParticipantState {
        let isSpatial: Bool
        let position: SIMD3<Float>?
        let orientation: simd_quatf?
    }
    
    @Published var localParticipantState: ParticipantState?
    
    static let shared = SystemCoordinator()
    
    private init() {
        // Initialize with default spatial state
        localParticipantState = ParticipantState(isSpatial: true, position: nil, orientation: nil)
    }
    
    func updateLocalParticipantState(isSpatial: Bool, position: SIMD3<Float>? = nil, orientation: simd_quatf? = nil) {
        localParticipantState = ParticipantState(isSpatial: isSpatial, position: position, orientation: orientation)
    }
}

