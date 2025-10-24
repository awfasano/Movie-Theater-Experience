//
//  EventMessagingView.swift
//  Movie Theater Experience
//
//  Group messaging for all event participants
//

import SwiftUI
import FirebaseFirestore

struct EventMessagingView: View {
    let eventId: String
    @EnvironmentObject private var hostedEventManager: HostedEventManager

    @State private var messages: [EventMessage] = []
    @State private var newMessageText = ""
    @State private var isLoading = true

    private let db = Firestore.firestore(database: "uploads")

    var currentUserName: String {
        hostedEventManager.participants.first(where: { $0.id == AppModel.shared.currentUserId })?.userName ?? "Anonymous"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.blue)
                Text("Event Chat")
                    .font(.headline)
                Spacer()
                Text("\(messages.count) messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if isLoading {
                            ProgressView("Loading messages...")
                                .padding()
                        } else if messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No messages yet")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Be the first to say something!")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 40)
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(
                                    message: message,
                                    isCurrentUser: message.senderId == AppModel.shared.currentUserId
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { oldCount, newCount in
                    if newCount > oldCount, let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Message input
            HStack(spacing: 12) {
                TextField("Type a message...", text: $newMessageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                }
                .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .task {
            await loadMessages()
            startMessageListener()
        }
    }

    private func loadMessages() async {
        do {
            let snapshot = try await db.collection("Events")
                .document(eventId)
                .collection("messages")
                .order(by: "timestamp", descending: false)
                .limit(to: 100)
                .getDocuments()

            let loadedMessages = snapshot.documents.compactMap { doc -> EventMessage? in
                try? doc.data(as: EventMessage.self)
            }

            await MainActor.run {
                messages = loadedMessages
                isLoading = false
            }

            print("📨 [Messaging] Loaded \(loadedMessages.count) messages")
        } catch {
            print("❌ [Messaging] Failed to load messages: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func startMessageListener() {
        db.collection("Events")
            .document(eventId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                guard let snapshot = snapshot else {
                    print("❌ [Messaging] Listener error: \(error?.localizedDescription ?? "Unknown")")
                    return
                }

                snapshot.documentChanges.forEach { change in
                    if change.type == .added {
                        if let message = try? change.document.data(as: EventMessage.self) {
                            // Only add if not already in array
                            if !messages.contains(where: { $0.id == message.id }) {
                                messages.append(message)
                                messages.sort { $0.timestamp < $1.timestamp }
                            }
                        }
                    }
                }
            }
    }

    private func sendMessage() {
        let trimmedMessage = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        let message = EventMessage(
            senderId: AppModel.shared.currentUserId,
            senderName: currentUserName,
            text: trimmedMessage,
            timestamp: Date()
        )

        Task {
            do {
                try db.collection("Events")
                    .document(eventId)
                    .collection("messages")
                    .document(message.id)
                    .setData(from: message)

                print("✅ [Messaging] Sent message: \(trimmedMessage)")

                await MainActor.run {
                    newMessageText = ""
                }
            } catch {
                print("❌ [Messaging] Failed to send message: \(error)")
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: EventMessage
    let isCurrentUser: Bool

    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser {
                    Text(message.senderName)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }

                Text(message.text)
                    .font(.body)
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isCurrentUser ? Color.blue : Color(.secondarySystemBackground))
                    .cornerRadius(16)

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isCurrentUser {
                Spacer()
            }
        }
    }
}

// MARK: - Event Message Model

struct EventMessage: Identifiable, Codable {
    let id: String
    let senderId: String
    let senderName: String
    let text: String
    let timestamp: Date

    init(id: String = UUID().uuidString, senderId: String, senderName: String, text: String, timestamp: Date) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
    }
}
