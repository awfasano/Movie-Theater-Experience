// Add Firestore-backed consensus/final answer submission and listener
// Make sure listenForSubmissions() is called in init

import Foundation
import Combine
import FirebaseFirestore

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

    let tableNumber: Int
    let maxVotes: Int
    let question: TriviaQuestion
    let userId: String
    let eventId: String
    private var votesListener: ListenerRegistration?
    private var submissionListener: ListenerRegistration?
    private let db = Firestore.firestore(database: "uploads")

    init(tableNumber: Int, maxVotes: Int = 4, question: TriviaQuestion, userId: String, eventId: String) {
        self.tableNumber = tableNumber
        self.maxVotes = maxVotes
        self.question = question
        self.userId = userId
        self.eventId = eventId
        listenForVotes()
        listenForSubmissions() // New: listen for answer submissions
    }

    deinit { votesListener?.remove(); submissionListener?.remove() }

    func submitVote(_ answer: Int) {
        userVote = answer
        userVotes[userId] = answer
        let ref = db.collection("Events").document(eventId)
            .collection("tables").document("\(tableNumber)")
            .collection("votes").document(userId)
        ref.setData(["vote": answer])
    }

    func submitConsensus() {
        guard let consensus = consensus else { return }
        let ref = db.collection("Events").document(eventId)
            .collection("tables").document("\(tableNumber)")
            .collection("submissions").document(question.id)
        ref.setData(["answer": consensus, "submittedBy": userId, "timestamp": Date()]) { [weak self] _ in
            self?.answerSubmitted = true
            self?.finalAnswer = consensus
        }
    }

    private func listenForVotes() {
        let ref = db.collection("Events").document(eventId)
            .collection("tables").document("\(tableNumber)")
            .collection("votes")
        votesListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let docs = snapshot?.documents else { return }
            var voteMap: [String: Int] = [:]
            for doc in docs { if let v = doc.data()["vote"] as? Int { voteMap[doc.documentID] = v } }
            self.userVotes = voteMap
            self.recalculateVotes()
        }
    }

    private func listenForSubmissions() {
        let ref = db.collection("Events").document(eventId)
            .collection("tables").document("\(tableNumber)")
            .collection("submissions").document(question.id)
        submissionListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else { return }
            if let answer = data["answer"] as? Int {
                self.finalAnswer = answer
                self.answerSubmitted = true
            }
        }
    }

    private func recalculateVotes() {
        var counts: [Int: Int] = [:]
        for vote in userVotes.values { counts[vote, default: 0] += 1 }
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

    func getVoters(for answer: Int) -> [String] {
        teamMembers.filter { userVotes[$0.id] == answer }.map { $0.userName }
    }
}
