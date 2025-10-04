//
//  TableFaceTimeJoinButton.swift
//  Movie Theater Experience
//
//  Button for participants to join their table's FaceTime call
//

import SwiftUI
import FirebaseFirestore

struct TableFaceTimeJoinButton: View {
    let tableNumber: Int
    @State private var faceTimeURL: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore(database: "uploads")

    var body: some View {
        VStack(spacing: 8) {
            Button(action: {
                Task {
                    await joinTableFaceTime()
                }
            }) {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Join Table Call")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || faceTimeURL == nil)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if faceTimeURL == nil {
                Text("No FaceTime link available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            Task {
                await fetchFaceTimeLink()
            }
        }
    }

    // MARK: - Actions

    private func fetchFaceTimeLink() async {
        isLoading = true
        errorMessage = nil

        do {
            // Get current event and generate room code
            guard let event = HostedEventManager.shared.currentEvent,
                  let eventId = event.id else {
                print("⚠️ No current event")
                errorMessage = "No active event"
                isLoading = false
                return
            }

            let activity = TriviaEventActivity(
                eventId: eventId,
                eventTitle: event.title,
                spaceId: eventId
            )

            let roomCode = TriviaEventActivity.generateTableRoomCode(
                sessionCode: activity.sessionCode,
                tableNumber: tableNumber
            )

            // Fetch FaceTime URL from Firebase
            let snapshot = try await db.collection("TableVoiceRooms")
                .document(roomCode)
                .getDocument()

            if let data = snapshot.data(),
               let url = data["faceTimeURL"] as? String {
                await MainActor.run {
                    faceTimeURL = url
                    print("✅ [Participant] Fetched FaceTime link for table \(tableNumber)")
                }
            } else {
                await MainActor.run {
                    errorMessage = "Link not set up yet"
                    print("⚠️ [Participant] No FaceTime link for table \(tableNumber)")
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load link"
                print("❌ [Participant] Error fetching FaceTime link: \(error)")
            }
        }

        isLoading = false
    }

    private func joinTableFaceTime() async {
        guard let urlString = faceTimeURL,
              let url = URL(string: urlString) else {
            errorMessage = "Invalid FaceTime link"
            return
        }

        await MainActor.run {
            UIApplication.shared.open(url) { success in
                if success {
                    print("✅ [Participant] Opened FaceTime link for table \(tableNumber)")
                } else {
                    errorMessage = "Failed to open FaceTime"
                    print("❌ [Participant] Failed to open FaceTime link")
                }
            }
        }
    }
}

// MARK: - Standalone View Version

struct TableFaceTimeJoinView: View {
    let tableNumber: Int
    @EnvironmentObject private var hostedEventManager: HostedEventManager

    var currentTable: EventTable? {
        hostedEventManager.tables.first(where: { $0.tableNumber == tableNumber })
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "video.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)

                if let table = currentTable {
                    Text(table.teamName ?? "Table \(tableNumber)")
                        .font(.title2.bold())

                    Text("\(table.participants.count) participants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Join Button
            TableFaceTimeJoinButton(tableNumber: tableNumber)

            // Info
            Text("Join your table's FaceTime call to talk with your teammates")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}

// MARK: - Preview

#if DEBUG
struct TableFaceTimeJoinButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TableFaceTimeJoinButton(tableNumber: 1)
                .padding()

            TableFaceTimeJoinView(tableNumber: 1)
                .environmentObject(HostedEventManager.shared)
                .padding()
        }
    }
}
#endif
