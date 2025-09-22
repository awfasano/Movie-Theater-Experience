//
//  SharePlayManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/17/25.
//

import Foundation
// SharePlay/SharePlayManager.swift
import GroupActivities
import Combine

@MainActor
class TriviaSharePlayManager: ObservableObject {
    static let shared = TriviaSharePlayManager()
    
    @Published var isSessionActive = false
    @Published var participants: Set<Participant> = []
    @Published var localParticipantID: Participant.ID?
    
    private var groupSession: GroupSession<TriviaEventActivity>?
    private var messenger: GroupSessionMessenger?
    private var subscriptions = Set<AnyCancellable>()
    
    func startSession(for activity: TriviaEventActivity) async {
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            do {
                _ = try await activity.activate()
            } catch {
                print("Failed to activate activity: \(error)")
            }
        case .activationDisabled:
            print("SharePlay is disabled")
        default:
            break
        }
    }
    
    func configureGroupSession(_ session: GroupSession<TriviaEventActivity>) {
        self.groupSession = session
        self.isSessionActive = true
        
        // Set up messenger
        self.messenger = GroupSessionMessenger(session: session)
        
        // Track participants
        session.$activeParticipants
            .sink { [weak self] (participants: Set<Participant>) in
                self?.participants = participants
            }
            .store(in: &subscriptions)
        
        // Set local participant (if available on this SDK)
        if let local: Participant? = (session as AnyObject).value(forKey: "localParticipant") as? Participant {
            self.localParticipantID = local?.id
        }
        // Fallback: localParticipant API may not be available on this SDK
        
        // Join the session
        session.join()
    }
    
    func sendMessage<T: Codable>(_ message: T) async {
        guard let messenger = messenger else { return }
        do {
            try await messenger.send(message)
        } catch {
            print("Failed to send message: \(error)")
        }
    }
    
    func endSession() {
        groupSession?.end()
        groupSession = nil
        messenger = nil
        isSessionActive = false
        participants.removeAll()
        localParticipantID = nil
    }
}
