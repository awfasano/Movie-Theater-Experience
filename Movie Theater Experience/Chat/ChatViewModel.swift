//
//  ChatViewModel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/8/24.
//

import FirebaseFirestore
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    private let db = Firestore.firestore(database: "movieexperiencedb")
    private var listener: ListenerRegistration?
    let chatId: String

    init(chatId: String) {
        self.chatId = chatId
        startListener()
    }
    
    func startListener() {
        listener = db.collection("chats").document("QcPNh74TgJuKw8eoIXkl").collection("messages")
            .order(by: "timestamp", descending: 
                    false) // Assuming you have timestamps and want to sort by it
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching chat: \(error)")
                } else if let snapshot = snapshot, !snapshot.isEmpty {
                    // Loop through document changes
                    snapshot.documentChanges.forEach { change in
                        let doc = change.document
                        guard let timestamp = doc.get("timestamp") as? Timestamp else { return }
                        let chatMessage = ChatMessage(id: doc.documentID,
                                                      timestamp: timestamp.dateValue(),
                                                      content: doc.get("content") as? String ?? "",
                                                      senderId: doc.get("senderId") as? String ?? "",
                                                      senderName: doc.get("senderName") as? String ?? "")
                        switch change.type {
                        case .added:
                            //print("is added")
                            if !self!.messages.contains(where: { $0.id == chatMessage.id }) {
                                self?.messages.append(chatMessage)
                                //print("hello?")
                            }
                        case .modified:
                            if let index = self?.messages.firstIndex(where: { $0.id == chatMessage.id }) {
                                self?.messages[index] = chatMessage
                            }
                        case .removed:
                            self?.messages.removeAll(where: { $0.id == chatMessage.id })
                        }
                    }
                    self?.messages.sort(by: { $0.timestamp < $1.timestamp }) // Sorting after updates
                }
            }
    }

    // Function to send a message (you'll need to implement this)
    func sendMessage(text: String) {
        guard !text.isEmpty else { return }

        let newMessageData = [
            "content": text,
            "timestamp": Timestamp(date: Date()),
            "senderId": "currentUserId",
            "senderName": "Anthony"
        ] as [String : Any]

        //  Create a new document within the "chats" collection
        db.collection("chats").document("QcPNh74TgJuKw8eoIXkl").collection("messages").addDocument(data: newMessageData) { error in
            if let error = error {
                print("Error sending message: \(error)")
            } else {
                print("Message sent successfully!")
            }
        }
    }
    
    func updateMessagePosition(id: String, yPosition: CGFloat) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].yPosition = yPosition
        }
    }

    func updateMessageOpacity(id: String, opacity: CGFloat) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].opacityCalc = opacity
        }
    }
    func getOpacity(id: String) -> CGFloat {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            return messages[index].opacityCalc
        }
        return 1
    }
    deinit {
        listener?.remove() // Stop listener when view model is deallocated
    }
}
