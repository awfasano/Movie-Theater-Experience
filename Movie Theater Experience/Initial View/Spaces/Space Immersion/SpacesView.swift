import RealityKit
import SwiftUI

struct SpacesView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var selectedSpace: SelectedSpace
    
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var currentSeat: String = "seat_1"
    @State private var spaceEntity: Entity?
    
    // Use the shared instance directly
    private var spaceManager = ImmersiveSpaceManager.shared
    private var spaceService = SpaceService()
    
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    
    // Current space from either source
    private var currentSpace: SpaceData? {
        return appModel.selectedSpace ?? selectedSpace.space
    }
    
    var body: some View {
        ZStack {
            // Main immersive content
            RealityView { content in
                // Configure immersive space manager
                configureImmersiveSpaceManager()
                
                // Check if we have an entity available
                if let entity = spaceEntity {
                    print("✅ Using loaded entity")
                    
                    // Clone the entity for use in immersive space
                    let clonedEntity = entity.clone(recursive: true)
                    
                    // Position user at seat_1
                    positionEntityForImmersion(clonedEntity)
                    
                    // Add to the scene
                    content.add(clonedEntity)
                    
                    // Update loading state
                    isLoading = false
                } else {
                    print("⚠️ No entity found")
                    loadError = SpaceServiceError.noData
                    isLoading = false
                }
            }
            
            // Loading, error, and UI overlays
            VStack {
                if isLoading {
                    // Loading overlay
                    VStack {
                        ProgressView()
                        Text("Entering space...")
                            .font(.headline)
                            .padding(.top, 8)
                    }
                    .padding(32)
                    .background(.regularMaterial)
                    .cornerRadius(16)
                } else if loadError != nil {
                    // Error overlay
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)
                        
                        Text("Failed to Enter Space")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Button("Return to Spaces") {
                            exitImmersiveSpace()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(32)
                    .background(.regularMaterial)
                    .cornerRadius(16)
                } else {
                    // Seat selection UI
                    VStack {
                        Spacer()
                        
                        HStack {
                            SeatSelectionPanel(currentSeat: $currentSeat) { seat in
                                switchToSeat(named: seat)
                            }
                            
                            Spacer()
                            
                            Button("Exit Space") {
                                exitImmersiveSpace()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .padding()
                            .background(.regularMaterial)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .onAppear {
            loadSpaceEntity()
        }
    }
    
    // Load the space entity directly from SpaceService
    private func loadSpaceEntity() {
        guard let space = currentSpace else {
            print("⚠️ No space selected")
            loadError = SpaceServiceError.noData
            isLoading = false
            return
        }
        
        spaceService.loadSpace(from: space) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let entity):
                    print("✅ Entity loaded successfully in SpacesView")
                    self.spaceEntity = entity
                    self.isLoading = false
                case .failure(let error):
                    print("⚠️ Failed to load entity: \(error)")
                    self.loadError = error
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Positioning Logic
    
    private func positionEntityForImmersion(_ entity: Entity) {
        print("📍 Positioning entity for immersion at seat: \(currentSeat)")
        
        // Find the seat entity
        guard let seat = entity.findEntity(named: currentSeat) else {
            print("⚠️ Could not find \(currentSeat) - using default positioning")
            spaceManager.setInitialUserPosition(
                position: SIMD3<Float>(0, 1.6, 0),
                orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            )
            return
        }
        
        // Reset entity position
        entity.position = .zero
        entity.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        
        // Get seat position
        let seatWorldPos = seat.position(relativeTo: nil)
        print("Seat world position: \(seatWorldPos)")
        
        // Calculate appropriate eye height
        let seatBounds = seat.visualBounds(relativeTo: nil)
        let seatHeight = seatBounds.max.y - seatBounds.min.y
        let realWorldSeatHeight: Float = 0.45  // Average seat height in meters
        let modelScale = seatHeight / realWorldSeatHeight
        let eyeHeightFromSeat: Float = 0.8 * modelScale  // Average seated eye height
        
        print("Seat height: \(seatHeight), Scale: \(modelScale), Eye height: \(eyeHeightFromSeat)")
        
        // Calculate position shift to align user with seat
        let shift = SIMD3<Float>(
            -seatWorldPos.x,
            -seatWorldPos.y - eyeHeightFromSeat,
            -seatWorldPos.z
        )
        entity.position = shift
        
        // Set user position in space manager
        spaceManager.setInitialUserPosition(
            position: SIMD3<Float>(0, 0, 0),
            orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        )
        
        print("📍 Positioning complete")
    }
    
    // MARK: - Actions
    
    private func switchToSeat(named seatName: String) {
        print("🪑 Switching to seat: \(seatName)")
        currentSeat = seatName
        
        // Find the entity in the scene and reposition
        guard let entity = spaceEntity?.clone(recursive: true) else {
            print("⚠️ Cannot switch seats - entity not found")
            return
        }
        
        // Find the seat entity
        guard let seat = entity.findEntity(named: seatName) else {
            print("⚠️ Seat \(seatName) not found")
            return
        }
        
        // Calculate seat position
        let seatPosition = seat.position(relativeTo: nil)
        let seatBounds = seat.visualBounds(relativeTo: nil)
        let seatHeight = seatBounds.max.y - seatBounds.min.y
        let realWorldSeatHeight: Float = 0.45
        let modelScale = seatHeight / realWorldSeatHeight
        let eyeHeightFromSeat: Float = 0.8 * modelScale
        
        // Calculate shift
        let shift = SIMD3<Float>(
            -seatPosition.x,
            -seatPosition.y - eyeHeightFromSeat,
            -seatPosition.z
        )
        
        // Apply the shift with animation
        withAnimation(.smooth(duration: 0.8)) {
            entity.position = shift
        }
        
        print("🪑 Switched to seat: \(seatName)")
    }
    
    private func exitImmersiveSpace() {
        Task {
            // Trigger ImmersiveSpaceManager's cleanup sequence
            await spaceManager.initiateCleanup()
        }
    }
    
    // MARK: - Helper Methods
    
    private func configureImmersiveSpaceManager() {
        spaceManager.configure(
            dismissImmersiveSpace: { [appModel] in
                appModel.immersiveSpaceWillClose()
                await dismissImmersiveSpace()
                appModel.immersiveSpaceDidClose()
            },
            dismissWindow: { windowId in
                // Add your window dismissal logic if needed
            },
            openWindow: { [openWindow] windowId in
                openWindow(id: windowId)
            },
            openImmersiveSpace: { [appModel] in
                appModel.immersiveSpaceWillOpen()
                return true
            }
        )
    }
}

// MARK: - Supporting Views

struct SeatSelectionPanel: View {
    @Binding var currentSeat: String
    var onSeatSelected: (String) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(["seat_1", "seat_2", "seat_3"], id: \.self) { seat in
                Button {
                    currentSeat = seat
                    onSeatSelected(seat)
                } label: {
                    HStack {
                        Image(systemName: currentSeat == seat ? "chair.lounge.fill" : "chair.lounge")
                        Text(seat.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(currentSeat == seat ? .blue : .secondary.opacity(0.5))
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}
