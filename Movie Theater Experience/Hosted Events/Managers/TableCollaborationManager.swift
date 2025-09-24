//
//  Fixed TableCollaborationManager.swift
//  Movie Theater Experience
//
//  Integrates SharePlay for real-time voting feedback - Fixed compilation errors
//

import Foundation
import Combine
import FirebaseFirestore
import SwiftUI // ADDED: Required for withAnimation

@MainActor
class TableCollaborationManager: ObservableObject {
    @Published var userVote: Int? = nil
    @Published var votes: [Int: Int] = [:]
    @Published var userVotes: [String: Int] = [:]
    @Published var teamMembers: [TeamMember] = []
    @Published var consensus: Int? = nil
    @Published var totalVotes: Int = 0
    @Published var canSubmit: Bool = false
    @Published var answerSubmitted: Bool = false
    @Published var finalAnswer: Int? = nil
    
    // SharePlay integration
    @Published var liveVotes: [String: Int] = [:] // Real-time votes via SharePlay
    @Published var showVoteAnimation: Bool = false

    let tableNumber: Int
    let maxVotes: Int
    let question: TriviaQuestion
    let userId: String
    let eventId: String
    
    private var votesListener: ListenerRegistration?
    private var submissionListener: ListenerRegistration?
    private var sharePlayCancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore(database: "uploads")

    init(tableNumber: Int, maxVotes: Int = 4, question: TriviaQuestion, userId: String, eventId: String) {
        self.tableNumber = tableNumber
        self.maxVotes = maxVotes
        self.question = question
        self.userId = userId
        self.eventId = eventId
        
        setupFirebaseListeners()
        setupSharePlayListeners()
    }

    deinit {
        // FIXED: Use Task to call MainActor methods from deinit
        Task { @MainActor in
            cleanup()
        }
    }
    
    private func cleanup() {
        votesListener?.remove()
        submissionListener?.remove()
        sharePlayCancellables.removeAll()
    }
    
    // MARK: - SharePlay Integration
    
    private func setupSharePlayListeners() {
        // Listen for SharePlay vote messages
        NotificationCenter.default.publisher(for: .sharePlayVoteReceived)
            .compactMap { $0.object as? VoteMessage }
            .filter { [weak self] vote in
                vote.tableNumber == self?.tableNumber
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vote in
                self?.handleSharePlayVote(vote)
            }
            .store(in: &sharePlayCancellables)
            
        // Listen for table consensus messages
        NotificationCenter.default.publisher(for: .sharePlayTableConsensus)
            .compactMap { $0.object as? TableConsensusMessage }
            .filter { [weak self] consensus in
                consensus.tableNumber == self?.tableNumber
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] consensus in
                self?.handleSharePlayConsensus(consensus)
            }
            .store(in: &sharePlayCancellables)
    }
    
    private func handleSharePlayVote(_ vote: VoteMessage) {
        print("📥 [TableCollaboration] Received SharePlay vote: \(vote.userName) -> \(vote.answer)")
        
        // Update live votes for immediate UI feedback
        liveVotes[vote.userId] = vote.answer
        
        // FIXED: Show vote animation
        withAnimation(.spring(response: 0.5)) {
            showVoteAnimation = true
        }
        
        // Hide animation after delay
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation {
                self.showVoteAnimation = false
            }
        }
        
        // Update team member if they exist
        if let memberIndex = teamMembers.firstIndex(where: { $0.id == vote.userId }) {
            teamMembers[memberIndex].currentVote = vote.answer
            teamMembers[memberIndex].hasVoted = true
        }
        
        recalculateLiveVotes()
    }
    
    private func handleSharePlayConsensus(_ consensus: TableConsensusMessage) {
        print("✅ [TableCollaboration] SharePlay consensus received: \(consensus.finalAnswer)")
        
        // FIXED: Show immediate feedback
        withAnimation(.spring()) {
            finalAnswer = consensus.finalAnswer
            answerSubmitted = true
        }
    }
    
    private func recalculateLiveVotes() {
        // Merge SharePlay live votes with Firebase votes
        let allVotes = userVotes.merging(liveVotes) { firebase, shareplay in
            // Prefer more recent SharePlay data for immediate feedback
            return shareplay
        }
        
        var counts: [Int: Int] = [:]
        for vote in allVotes.values {
            counts[vote, default: 0] += 1
        }
        
        votes = counts
        totalVotes = allVotes.count
        
        // Check for consensus (3+ votes for same answer)
        if let (majority, count) = counts.max(by: { $0.value < $1.value }), count >= 3 {
            consensus = majority
            canSubmit = true
        } else {
            consensus = nil
            canSubmit = false
        }
    }

    // MARK: - Enhanced Vote Submission
    
    func submitVote(_ answer: Int) {
        print("🗳️ [TableCollaboration] Submitting vote: \(answer)")
        
        userVote = answer
        
        // 1. Immediate SharePlay feedback for responsive UI
        Task {
            await TriviaSharePlayManager.shared.sendVote(
                userId: userId,
                userName: AppModel.shared.username,
                tableNumber: tableNumber,
                answer: answer
            )
        }
        
        // 2. Store in Firebase for persistence
        let ref = db.collection("Events").document(eventId)
            .collection("tables").document("\(tableNumber)")
            .collection("votes").document(userId)
        
        ref.setData(["vote": answer]) { error in
            if let error = error {
                print("❌ [TableCollaboration] Firebase vote error: \(error)")
            } else {
                print("✅ [TableCollaboration] Vote saved to Firebase")
            }
        }
    }

    // MARK: - Enhanced Consensus Submission
    
    func submitConsensus() {
        guard let consensus = consensus else {
            print("⚠️ [TableCollaboration] No consensus to submit")
            return
        }
        
        print("📤 [TableCollaboration] Submitting consensus: \(consensus)")
        
        // 1. Immediate SharePlay notification
        Task {
            await TriviaSharePlayManager.shared.sendTableConsensus(
                tableNumber: tableNumber,
                finalAnswer: consensus,
                submittedBy: userId
            )
        }
        
        // 2. Store in Firebase
        let ref = db.collection("Events").document(eventId)
            .collection("tables").document("\(tableNumber)")
            .collection("submissions").document(question.id)
        
        let submissionData: [String: Any] = [
            "answer": consensus,
            "submittedBy": userId,
            "timestamp": Date()
        ]
        
        ref.setData(submissionData) { [weak self] error in
            if let error = error {
                print("❌ [TableCollaboration] Consensus submission error: \(error)")
            } else {
                print("✅ [TableCollaboration] Consensus saved to Firebase")
                Task { @MainActor in
                    self?.answerSubmitted = true
                    self?.finalAnswer = consensus
                }
            }
        }
    }
    
    // MARK: - Firebase Listeners (existing code, enhanced)
    
    private func setupFirebaseListeners() {
        listenForVotes()
        listenForSubmissions()
    }

    private func listenForVotes() {
        let ref = db.collection("Events").document(eventId)
            .collection("tables").document("\(tableNumber)")
            .collection("votes")
            
        votesListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let docs = snapshot?.documents else { return }
            
            var voteMap: [String: Int] = [:]
            for doc in docs {
                if let vote = doc.data()["vote"] as? Int {
                    voteMap[doc.documentID] = vote
                }
            }
            
            Task { @MainActor in
                self.userVotes = voteMap
                self.recalculateVotes()
            }
        }
    }

    private func listenForSubmissions() {
        let ref = db.collection("Events").document(eventId)
            .collection("tables").document("\(tableNumber)")
            .collection("submissions").document(question.id)
            
        submissionListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else { return }
            
            Task { @MainActor in
                if let answer = data["answer"] as? Int {
                    self.finalAnswer = answer
                    self.answerSubmitted = true
                }
            }
        }
    }

    private func recalculateVotes() {
        // Use Firebase data as the authoritative source
        var counts: [Int: Int] = [:]
        for vote in userVotes.values {
            counts[vote, default: 0] += 1
        }
        
        votes = counts
        totalVotes = userVotes.count
        
        if let (majority, count) = counts.max(by: { $0.value < $1.value }), count >= 3 {
            consensus = majority
            canSubmit = true
        } else {
            consensus = nil
            canSubmit = false
        }
    }

    // MARK: - Helper Methods
    
    func getVoters(for answer: Int) -> [String] {
        // Include both Firebase and live SharePlay votes
        let allVotes = userVotes.merging(liveVotes) { firebase, _ in firebase }
        return teamMembers.filter { allVotes[$0.id] == answer }.map { $0.userName }
    }
    
    func hasUserVoted(_ userId: String) -> Bool {
        return userVotes[userId] != nil || liveVotes[userId] != nil
    }
    
    func getUserVote(_ userId: String) -> Int? {
        return userVotes[userId] ?? liveVotes[userId]
    }
}
