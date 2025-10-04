//
//  EventJoinFlowView.swift
//  Movie Theater Experience
//
//  Complete join flow for events with host/participant selection
//

import SwiftUI

struct EventJoinFlowView: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hostedEventManager: HostedEventManager

    @State private var selectedRole: JoinRole?
    @State private var hostPassword = ""
    @State private var showPasswordError = false
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var hasJoinedSuccessfully = false

    // Hard-coded host password for testing
    private let correctHostPassword = "trivia123"

    enum JoinRole: String, CaseIterable {
        case host = "Host"
        case participant = "Participant"

        var icon: String {
            switch self {
            case .host: return "person.crop.circle.badge.checkmark"
            case .participant: return "person.crop.circle"
            }
        }

        var description: String {
            switch self {
            case .host:
                return "Control the event, manage tables, and run the trivia game"
            case .participant:
                return "Join a table with friends and play trivia"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    eventHeaderSection
                    roleSelectionSection

                    if selectedRole == .host {
                        hostPasswordSection
                    }

                    if let role = selectedRole {
                        joinButtonSection(role: role)
                    }

                    if let error = joinError {
                        errorSection(message: error)
                    }
                }
                .padding()
            }
            .navigationTitle("Join Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $hasJoinedSuccessfully) {
                if selectedRole == .host {
                    HostExperienceView(event: event)
                        .environmentObject(hostedEventManager)
                } else {
                    ParticipantExperienceView(event: event)
                        .environmentObject(hostedEventManager)
                }
            }
        }
    }

    // MARK: - Event Header

    private var eventHeaderSection: some View {
        VStack(spacing: 12) {
            Image(systemName: event.eventIcon)
                .font(.system(size: 60))
                .foregroundColor(event.eventColor)

            Text(event.title)
                .font(.title2.bold())

            Text(event.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Event details
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "clock")
                    Text(event.formattedTimeRange)
                }
                .font(.caption)

                HStack {
                    Image(systemName: "person.2")
                    Text("\(event.currentParticipants)/\(event.maxParticipants) participants")
                }
                .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }

    // MARK: - Role Selection

    private var roleSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How would you like to join?")
                .font(.headline)

            ForEach(JoinRole.allCases, id: \.self) { role in
                RoleCard(
                    role: role,
                    isSelected: selectedRole == role,
                    onTap: {
                        withAnimation {
                            selectedRole = role
                            showPasswordError = false
                            joinError = nil
                        }
                    }
                )
            }
        }
    }

    // MARK: - Host Password

    private var hostPasswordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Host Password")
                .font(.headline)

            Text("Enter the host password to control this event")
                .font(.caption)
                .foregroundColor(.secondary)

            SecureField("Enter password", text: $hostPassword)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()

            if showPasswordError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Incorrect password")
                }
                .font(.caption)
                .foregroundColor(.red)
            }

            // Test hint
            Text("Test password: \(correctHostPassword)")
                .font(.caption2)
                .foregroundColor(.green)
                .padding(8)
                .background(.green.opacity(0.1))
                .cornerRadius(6)
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Join Button

    private func joinButtonSection(role: JoinRole) -> some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await joinEvent(as: role)
                }
            } label: {
                HStack {
                    if isJoining {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: role.icon)
                        Text("Join as \(role.rawValue)")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isJoining || (role == .host && hostPassword.isEmpty))
            .controlSize(.large)
        }
    }

    // MARK: - Error Section

    private func errorSection(message: String) -> some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
            Text(message)
                .font(.caption)
        }
        .foregroundColor(.red)
        .padding()
        .background(.red.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Join Logic

    private func joinEvent(as role: JoinRole) async {
        isJoining = true
        joinError = nil
        showPasswordError = false

        // Validate host password if joining as host
        if role == .host {
            guard hostPassword == correctHostPassword else {
                await MainActor.run {
                    showPasswordError = true
                    isJoining = false
                }
                return
            }
        }

        // Join the event
        let result = await hostedEventManager.joinHostedEvent(event)

        switch result {
        case .success(let participant):
            print("✅ [Join] Successfully joined event as \(role.rawValue)")
            print("   Participant ID: \(participant.userId)")

            // Note: isHost is computed based on participant role, not set directly
            // The role is determined by password authentication above

            await MainActor.run {
                hasJoinedSuccessfully = true
                isJoining = false
            }

        case .failure(let error):
            await MainActor.run {
                joinError = "Failed to join: \(error)"
                isJoining = false
            }
            print("❌ [Join] Failed to join event: \(error)")
        }
    }
}

// MARK: - Role Card

struct RoleCard: View {
    let role: EventJoinFlowView.JoinRole
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: role.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? .blue.opacity(0.1) : .gray.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(role.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(role.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? .blue.opacity(0.05) : .gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct EventJoinFlowView_Previews: PreviewProvider {
    static var previews: some View {
        EventJoinFlowView(event: CalendarEvent(
            title: "Friday Night Trivia",
            description: "Join us for an exciting trivia night!",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        ))
        .environmentObject(HostedEventManager.shared)
    }
}
#endif
