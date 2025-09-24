//
//  Fixed TriviaSpaceView.swift
//  Movie Theater Experience
//
//  Trivia immersive space with SharePlay integration - Fixed compilation errors
//

import SwiftUI
import RealityKit
import RealityKitContent

struct TriviaSpaceView: View {
    @EnvironmentObject private var personaManager: PersonaTableManager
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var triviaSharePlayManager: TriviaSharePlayManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var showParticipantsList = false
    @State private var isInitialized = false

    var body: some View {
        ZStack {
            // Main RealityView - FIXED: Removed async from closure signatures
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
            await initializeSharePlay()
        }
        .sheet(isPresented: $showParticipantsList) {
            SharePlayParticipantsView()
                .environmentObject(triviaSharePlayManager)
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
                
                // SharePlay Participants Button
                if triviaSharePlayManager.isSessionActive {
                    Button {
                        showParticipantsList = true
                    } label: {
                        HStack {
                            Image(systemName: "shareplay")
                                .foregroundColor(.green)
                            Text("\(triviaSharePlayManager.participants.count)")
                                .fontWeight(.medium)
                        }
                        .padding(12)
                        .background(.green.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
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
                    
                    Text("\(hostedEventManager.participants.count) participants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // SharePlay Status
                sharePlayStatusView
                
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
    
    private var sharePlayStatusView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(triviaSharePlayManager.isSessionActive ? .green : .orange)
                .frame(width: 8, height: 8)
            
            Text(triviaSharePlayManager.isSessionActive ? "SharePlay Active" : "SharePlay Starting...")
                .font(.caption)
                .foregroundColor(triviaSharePlayManager.isSessionActive ? .green : .orange)
            
            if triviaSharePlayManager.isSessionActive {
                Text("• \(triviaSharePlayManager.participants.count) connected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
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
                    
                    Text(gameState.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(statusColor(for: gameState.status))
                        .fontWeight(.medium)
                }
            } else {
                Text("No active game")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - RealityKit Setup - FIXED: Made synchronous
    
    private func setupTriviaSpace(_ content: RealityViewContent) {
        guard !isInitialized else { return }
        
        // FIXED: Use Task for async operations inside sync function
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
        // FIXED: Use DirectionalLight instead of AmbientLightComponent
        let directionalLight = DirectionalLight()
        directionalLight.light.color = .white
        directionalLight.light.intensity = 1000
        directionalLight.orientation = simd_quatf(angle: .pi/4, axis: [1, 0, 0])
        content.add(directionalLight)
        
        // Add point light for better illumination
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
        entity.position = table.tablePosition
        
        // Add table number text
        // Note: In a real implementation, you'd use TextMeshGenerator or similar
        
        return entity
    }
    
    // FIXED: Made synchronous
    private func updatePersonaPositions(_ content: RealityViewContent) {
        // Update persona positions based on participant data
        // This would sync with the PersonaTableManager and SharePlay data
        
        for participant in hostedEventManager.participants {
            if let position = participant.personaPosition,
               let rotation = participant.personaRotation {
                // Update persona entity position if it exists
                // This is where you'd move the actual persona representations
            }
        }
    }
    
    // MARK: - SharePlay Integration
    
    private func initializeSharePlay() async {
        print("🎮 Initializing SharePlay for trivia space...")
        
        // Start SharePlay session if not already active
        if !hostedEventManager.sharePlayActive {
            let success = await hostedEventManager.startSharePlaySession()
            if success {
                print("✅ SharePlay session started successfully")
            } else {
                print("⚠️ SharePlay session failed to start")
            }
        }
        
        // Listen for SharePlay events specific to the immersive space
        setupSharePlayListeners()
    }
    
    private func setupSharePlayListeners() {
        // Listen for participant position updates
        NotificationCenter.default.addObserver(
            forName: .sharePlayVoteReceived,
            object: nil,
            queue: .main
        ) { notification in
            if let vote = notification.object as? VoteMessage {
                // Handle vote visualization in 3D space
                Task {
                    await self.visualizeVote(vote)
                }
            }
        }
        
        // Listen for emoji reactions
        NotificationCenter.default.addObserver(
            forName: Notification.Name("sharePlayEmojiReceived"),
            object: nil,
            queue: .main
        ) { notification in
            if let emoji = notification.object as? EmojiReactionMessage {
                // Trigger 3D emoji effect
                Task {
                    await self.showEmojiEffect(emoji)
                }
            }
        }
    }
    
    private func visualizeVote(_ vote: VoteMessage) async {
        // Create a visual effect at the table where the vote occurred
        print("🗳️ Visualizing vote from table \(vote.tableNumber): answer \(vote.answer)")
        
        // In a real implementation, you'd create particle effects or UI indicators
        // positioned at the table location in 3D space
    }
    
    private func showEmojiEffect(_ emoji: EmojiReactionMessage) async {
        // Show emoji particle effect in 3D space
        print("😀 Showing emoji effect: \(emoji.emoji) at table \(emoji.tableNumber)")
        
        // FIXED: Added missing isLooping parameter
        SpacesEntityWrapper.shared.updateVolumetricEmojiTexture(with: emoji.emoji, isLooping: false)
    }
    
    // MARK: - Actions
    
    private func exitTriviaSpace() async {
        print("🚪 Exiting trivia space...")
        
        // Stop SharePlay session
        hostedEventManager.endSharePlaySession()
        
        // Dismiss immersive space
        await dismissImmersiveSpace()
    }
    
    // MARK: - Helper Methods
    
    private func statusColor(for status: GameStatus) -> Color {
        switch status {
        case .waiting:
            return .orange
        case .question_active:
            return .green
        case .finished:
            return .red
        }
    }
}

// MARK: - SharePlay Participants View

struct SharePlayParticipantsView: View {
    @EnvironmentObject private var triviaSharePlayManager: TriviaSharePlayManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("SharePlay Participants") {
                    if triviaSharePlayManager.participants.isEmpty {
                        Text("No participants connected")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(triviaSharePlayManager.participants), id: \.id) { participant in
                            HStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                
                                VStack(alignment: .leading) {
                                    Text("Participant")
                                        .font(.body)
                                    Text(participant.id.uuidString.prefix(8))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("SharePlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
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
            .environmentObject(TriviaSharePlayManager.shared)
    }
}
#endif
