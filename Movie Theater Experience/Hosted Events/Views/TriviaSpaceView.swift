//
//  TriviaSpaceView.swift
//  Movie Theater Experience
//
//  Trivia immersive space - Firebase-based, no SharePlay
//

import SwiftUI
import RealityKit
import RealityKitContent

struct TriviaSpaceView: View {
    @EnvironmentObject private var personaManager: PersonaTableManager
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var showParticipantsList = false
    @State private var isInitialized = false
    @State private var isConnected = false

    var body: some View {
        ZStack {
            // Main RealityView
            RealityView { content in
                setupTriviaSpace(content)
            } update: { content in
                updatePersonaPositions(content)
            }

            // UI Overlays
            VStack {
                topControlsOverlay
                Spacer()
                bottomStatusOverlay
            }
            .allowsHitTesting(true)
        }
        .task {
            await initializeSpace()
        }
        .sheet(isPresented: $showParticipantsList) {
            ParticipantsListView()
                .environmentObject(hostedEventManager)
        }
    }

    // MARK: - Top Controls

    private var topControlsOverlay: some View {
        HStack {
            Spacer()

            VStack(spacing: 12) {
                // Host Controls Button
                Button {
                    openWindow(id: "hostControls")
                } label: {
                    Label("Host Controls", systemImage: "person.crop.square.filled.and.at.rectangle")
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Participants Button
                Button {
                    showParticipantsList = true
                } label: {
                    HStack {
                        Image(systemName: "person.2")
                            .foregroundColor(.blue)
                        Text("\(hostedEventManager.participants.count)")
                            .fontWeight(.medium)
                    }
                    .padding(12)
                    .background(.blue.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Exit Button
                Button {
                    Task {
                        await exitTriviaSpace()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .padding(12)
                        .background(.red.opacity(0.2))
                        .clipShape(Circle())
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
    }

    // MARK: - Bottom Status

    private var bottomStatusOverlay: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                // Event Info
                if let event = hostedEventManager.currentEvent {
                    Text(event.title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(hostedEventManager.participants.count) participants • \(hostedEventManager.tables.count) tables")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Connection Status
                connectionStatusView

                // Game State
                gameStateView
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding()
    }

    private var connectionStatusView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? .green : .orange)
                .frame(width: 8, height: 8)

            Text(isConnected ? "Connected to Firebase" : "Connecting...")
                .font(.caption)
                .foregroundColor(isConnected ? .green : .orange)
        }
    }

    private var gameStateView: some View {
        Group {
            if let gameState = hostedEventManager.gameState {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Round \(gameState.currentRound)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Question \(gameState.currentQuestion ?? 0)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 1, height: 20)

                    Text(gameState.status.displayName)
                        .font(.caption)
                        .foregroundColor(gameState.status.color)
                        .fontWeight(.medium)
                }
            } else {
                Text("No active game")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - RealityKit Setup

    private func setupTriviaSpace(_ content: RealityViewContent) {
        guard !isInitialized else { return }

        Task {
            // Load base environment
            do {
                let triviaScene = try await Entity(named: "TriviaSpace", in: realityKitContentBundle)
                await MainActor.run {
                    content.add(triviaScene)
                    print("✅ Loaded trivia space scene")
                }
            } catch {
                print("❌ Failed to load trivia space: \(error)")
            }

            // Setup lighting
            await MainActor.run {
                setupLighting(content)
            }

            // Create table markers
            await createTableMarkers(content)

            await MainActor.run {
                isInitialized = true
            }
        }
    }

    private func setupLighting(_ content: RealityViewContent) {
        // Directional light
        let directionalLight = DirectionalLight()
        directionalLight.light.color = .white
        directionalLight.light.intensity = 1000
        directionalLight.orientation = simd_quatf(angle: .pi/4, axis: [1, 0, 0])
        content.add(directionalLight)

        // Point light for better illumination
        let pointLight = PointLight()
        pointLight.light.color = .white
        pointLight.light.intensity = 500
        pointLight.position = [0, 3, 0]
        content.add(pointLight)
    }

    private func createTableMarkers(_ content: RealityViewContent) async {
        await MainActor.run {
            for table in hostedEventManager.tables {
                Task {
                    let tableEntity = await createTableEntity(for: table)
                    await MainActor.run {
                        content.add(tableEntity)
                    }
                }
            }
        }
    }

    private func createTableEntity(for table: EventTable) async -> Entity {
        let entity = Entity()

        // Create table visual
        let mesh = MeshResource.generateBox(size: [1.5, 0.1, 1.0])
        let material = SimpleMaterial(color: .brown, isMetallic: false)
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])

        entity.components.set(modelComponent)
        entity.position = table.tablePosition.simd3

        // Add hover component for interactivity
        entity.components.set(HoverEffectComponent())

        return entity
    }

    private func updatePersonaPositions(_ content: RealityViewContent) {
        // Update persona positions based on participant data from Firebase
        for participant in hostedEventManager.participants {
            if let position = participant.personaPosition,
               let rotation = participant.personaRotation {
                // Update persona entity position if it exists
                // This syncs with PersonaTableManager
                // In a full implementation, you'd track entities by participant ID
            }
        }
    }

    // MARK: - Initialization

    private func initializeSpace() async {
        print("🎮 Initializing trivia space...")

        // Wait for event to be loaded
        guard hostedEventManager.currentEvent != nil else {
            print("⚠️ No current event - waiting...")
            return
        }

        // Setup Firebase listeners
        setupFirebaseListeners()

        // Mark as connected
        await MainActor.run {
            isConnected = true
        }

        print("✅ Trivia space initialized")
    }

    private func setupFirebaseListeners() {
        // Firebase listeners are already set up in HostedEventManager
        // This would be where you add any space-specific listeners

        print("👂 Firebase listeners active")
    }

    // MARK: - Actions

    private func exitTriviaSpace() async {
        print("🚪 Exiting trivia space...")

        // Cleanup
        await hostedEventManager.cleanupAudioRooms()

        // Dismiss immersive space
        await dismissImmersiveSpace()
    }
}

// MARK: - Participants List View

struct ParticipantsListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hostedEventManager: HostedEventManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if hostedEventManager.participants.isEmpty {
                        ContentUnavailableView(
                            "No Participants",
                            systemImage: "person.2.slash",
                            description: Text("Participants will appear here when they join the event")
                        )
                    } else {
                        ForEach(hostedEventManager.participants) { participant in
                            ParticipantRow(participant: participant)
                        }
                    }
                } header: {
                    Text("\(hostedEventManager.participants.count) Participants")
                }

                Section {
                    ForEach(hostedEventManager.tables.sorted(by: { $0.tableNumber < $1.tableNumber })) { table in
                        TableRow(table: table)
                    }
                } header: {
                    Text("Tables")
                }
            }
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Participant Row

struct ParticipantRow: View {
    let participant: EventParticipant

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.green)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(participant.userName)
                    .font(.body)

                HStack(spacing: 8) {
                    if let tableNumber = participant.tableNumber {
                        Label("Table \(tableNumber)", systemImage: "table.furniture")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No table assigned")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if participant.role == .host {
                        Text("HOST")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue)
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - Table Row

struct TableRow: View {
    let table: EventTable

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "table.furniture.fill")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(table.teamName ?? "Table \(table.tableNumber)")
                    .font(.body.bold())

                HStack(spacing: 12) {
                    Label("\(table.participants.count)/\(table.maxSeats)", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("\(table.currentScore) pts", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            }

            Spacer()

            if table.faceTimeLinkURL != nil {
                Image(systemName: "video.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "video.slash")
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TriviaSpaceView_Previews: PreviewProvider {
    static var previews: some View {
        TriviaSpaceView()
            .environmentObject(PersonaTableManager())
            .environmentObject(HostedEventManager.shared)
    }
}
#endif
