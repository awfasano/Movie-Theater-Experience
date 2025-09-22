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

// MARK: - SharePlayManager
@MainActor
class SharePlayManager: ObservableObject {
    static let shared = SharePlayManager()
    
    // MARK: - Published Properties
    @Published var isSessionActive: Bool = false
    @Published var participants: Set<Participant> = []
    @Published var localParticipantID: UUID?
    
    // MARK: - Private Properties
    private var groupSession: GroupSession<PublicSpaceActivity>?
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
        groupSession?.leave()
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
        // Observe public space sessions
        PublicSpaceActivity.sessions()
            .sink { [weak self] sessions in
                guard let self = self else { return }
                
                if let session = sessions.first {
                    self.configureGroupSession(session)
                } else {
                    self.cleanupSession()
                }
            }
            .store(in: &cancellables)
        
        // Observe direct call sessions
        DirectCallActivity.sessions()
            .sink { [weak self] sessions in
                guard let self = self else { return }
                
                if let session = sessions.first {
                    self.configureDirectCallSession(session)
                } else {
                    self.cleanupSession()
                }
            }
            .store(in: &cancellables)
    }
    
    private func configureGroupSession<ActivityType: GroupActivity>(_ session: GroupSession<ActivityType>) {
        sessionCancellables.removeAll()
        
        if let publicSpaceSession = session as? GroupSession<PublicSpaceActivity> {
            self.groupSession = publicSpaceSession
        } else if let directCallSession = session as? GroupSession<DirectCallActivity> {
            self.directCallSession = directCallSession
        }
        
        // Update session state
        session.$state
            .sink { [weak self] state in
                self?.handleSessionStateChange(state)
            }
            .store(in: &sessionCancellables)
        
        // Update participants
        session.$activeParticipants
            .sink { [weak self] participants in
                self?.updateParticipants(participants)
            }
            .store(in: &sessionCancellables)
        
        // Join the session
        session.join()
        
        print("SharePlay: Configured group session with \(session.activeParticipants.count) participants")
    }
    
    private func configureDirectCallSession(_ session: GroupSession<DirectCallActivity>) {
        configureGroupSession(session)
    }
    
    private func handleSessionStateChange(_ state: GroupSession<PublicSpaceActivity>.State) {
        switch state {
        case .waiting:
            print("SharePlay: Session is waiting")
            isSessionActive = false
        case .joined:
            print("SharePlay: Session joined successfully")
            isSessionActive = true
        case .invalidated(let reason):
            print("SharePlay: Session invalidated: \(reason)")
            isSessionActive = false
            cleanupSession()
        @unknown default:
            print("SharePlay: Unknown session state")
        }
    }
    
    private func updateParticipants<ActivityType: GroupActivity>(_ groupParticipants: Set<GroupSession<ActivityType>.Participant>) {
        // Convert GroupSession participants to our Participant model
        let newParticipants = Set(groupParticipants.map { groupParticipant in
            Participant(id: groupParticipant.id, name: nil) // Name might not be available
        })
        
        self.participants = newParticipants
        
        // Set local participant ID (assuming the first participant is local for now)
        if localParticipantID == nil, let firstParticipant = newParticipants.first {
            localParticipantID = firstParticipant.id
        }
        
        print("SharePlay: Updated participants count: \(newParticipants.count)")
    }
    
    private func cleanupSession() {
        sessionCancellables.removeAll()
        groupSession = nil
        directCallSession = nil
        isSessionActive = false
        participants.removeAll()
        localParticipantID = nil
        
        print("SharePlay: Session cleaned up")
    }
}

// MARK: - SystemCoordinator (Placeholder for spatial tracking)
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