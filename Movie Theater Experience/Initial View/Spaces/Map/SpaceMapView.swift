// MARK: - Seat Map View (Main View Structure)

import SwiftUI
import RealityKit
import RealityKitContent // Ensure this is imported

// MARK: - Seat Map View (Main View Structure)


enum SpaceMapResources {
    // Create meshes on demand instead of storing them
    static func createSphereMesh() -> MeshResource {
        MeshResource.generateSphere(radius: OrbMaterials.sphereRadius)
    }
    
    static func createHaloMesh() -> MeshResource {
        MeshResource.generateSphere(radius: OrbMaterials.sphereRadius)
    }

    static func sphereMaterial(for seat: SeatPosition,
                               selected: Bool) -> PhysicallyBasedMaterial {
        OrbMaterials.sphereMaterial(for: seat, isSelected: selected)
    }

    static func haloMaterial() -> PhysicallyBasedMaterial {
        OrbMaterials.halo()
    }

    static func prime(for space: SpaceData) async {
        if let url = URL(string: space.mapURL ?? "") {
            _ = try? await URLSession.shared.data(from: url)   // pre-decode
        }
        // Note: We can't pre-create meshes here due to RealityKit constraints
    }
}

struct SeatNode {            // keeps references so we avoid findEntity()
    let sphere: ModelEntity
    let halo:   ModelEntity
}


struct SpaceMapView: View {

    // MARK: ‑ Properties
    @Environment(AppModel.self) private var appModel // Access the shared app state

    // Local state for the view
    @State private var previousSeatId: String? = nil // Tracks the *last* selected ID for animation triggers
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var hoveredSeatId: String? = nil // <-- ADD THIS STATE
    @State private var seatEntities: [String: Entity] = [:]
    @State private var seatNodes: [String: SeatNode] = [:]
    @State private var currentSeatId: String? = "seat_1" // Default to seat_1
    @State private var resourcesReady = false

    
    // Map dimensions
    private let mapDisplayWidth: CGFloat = 1568
    private let mapDisplayHeight: CGFloat = 1024

    // MARK: - Body
    var body: some View {
        Group {
            if let errorMessage {
                errorView(message: errorMessage)
            } else if let space = appModel.selectedSpace, let seats = space.seats, !seats.isEmpty {
                // Directly call renderMap, which now contains the complete and unified logic
                renderMap(space: space, seats: seats)
            } else {
                ProgressView("Loading...")
                    .onAppear(perform: loadData)
            }
        }
        .onAppear {
            syncSelectedSeatFromModel()
            isLoading = appModel.selectedSpace?.seats == nil
            if !isLoading {
                DispatchQueue.main.async { isLoading = false }
            }
            previousSeatId = currentSeatId
        }
    }

    // MARK: - View Builders / Subviews

    /// Builds the main map view with background and the single RealityView for orbs
    @ViewBuilder
    private func renderMap(space: SpaceData, seats: [SeatPosition]) -> some View {
        VStack(spacing: 12) {
            ZStack {
                // 1. This background is now persistent and will not be redrawn.
                mapBackground(urlString: space.mapURL)

                // 2. Conditionally place content on top of the background.
                if resourcesReady {
                    RealityView { content in
                        await createSeatEntities(content: content, seats: seats)
                    } update: { content in
                        updateChangedSeats(content: content, seats: seats)
                    }
                    .gesture(
                        SpatialTapGesture()
                            .targetedToAnyEntity()
                            .onEnded { value in
                                if let seat = seats.first(where: {
                                    $0.id == value.entity.name ||
                                    $0.id == value.entity.parent?.name
                                }) {
                                    handleTap(on: seat)
                                }
                            }
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                } else {
                    // Show the loading overlay while resources are priming.
                    loadingOverlay
                }
            }
            .frame(width: mapDisplayWidth, height: mapDisplayHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8)
            .task {
                // 3. Attach the task to this stable view hierarchy.
                if !resourcesReady {
                    await preloadResources(for: space)
                    withAnimation {
                        resourcesReady = true
                    }
                }
            }

            selectedSeatLabel(seats: seats)
            seatPicker(seats: seats)
        }
        .padding()
    }
    // Create entities efficiently in batch
    @MainActor
    private func createSeatEntities(content: RealityViewContent, seats: [SeatPosition]) async {
        let sceneScale: Float = 1.0 / Float(mapDisplayWidth)
        let batchParent = Entity()

        for seat in seats {
            let isInitiallySelected = (seat.id == currentSeatId)

            let halo = ModelEntity(
                mesh: SpaceMapResources.createHaloMesh(),
                materials: [SpaceMapResources.haloMaterial()]
            )

            let sphere = ModelEntity(
                mesh: SpaceMapResources.createSphereMesh(),
                materials: [SpaceMapResources.sphereMaterial(for: seat, selected: isInitiallySelected)]
            )

            sphere.name = seat.id
            
            // Set position
            let x = (Float(seat.position.x) - Float(mapDisplayWidth / 2)) * sceneScale
            let y = (-Float(seat.position.y) + Float(mapDisplayHeight / 2)) * sceneScale
            let z = isInitiallySelected ? OrbMaterials.sphereRadius * 0.25 : 0
            sphere.position = [x, y, z]

            halo.name = seat.id + "-halo"
            halo.transform.scale = .init(repeating: OrbMaterials.haloFactor)
            halo.isEnabled = isInitiallySelected && seat.isAvailable
            sphere.addChild(halo)
            
            // Add collision and input components
            sphere.components.set(CollisionComponent(
                shapes: [.generateSphere(radius: OrbMaterials.sphereRadius)],
                mode: .trigger
            ))
            sphere.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            sphere.components.set(HoverEffectComponent())
            
            // Add to batch parent
            batchParent.addChild(sphere)
            
            // Store reference
            seatNodes[seat.id] = SeatNode(sphere: sphere, halo: halo)
        }

        // --- FIX IS HERE ---
        // Add the parent entity with all its children to the scene at once.
        // Do not move the children after this.
        content.add(batchParent)
    }
    
    
    private func updateChangedSeats(content: RealityViewContent, seats: [SeatPosition]) {
        // Only update seats that actually changed
        var toUpdate = Set<String>()
        if let prev = previousSeatId { toUpdate.insert(prev) }
        if let curr = currentSeatId { toUpdate.insert(curr) }
        
        // Batch material updates
        for seatId in toUpdate {
            guard let node = seatNodes[seatId],
                  let seat = seats.first(where: { $0.id == seatId }) else { continue }
            
            let isSelected = (seatId == currentSeatId)
            
            // Always update material (comparison not possible with materials)
            let newMaterial = SpaceMapResources.sphereMaterial(for: seat, selected: isSelected)
            node.sphere.model?.materials = [newMaterial]
            
            // Update halo and animation
            let showHalo = isSelected && seat.isAvailable
            if showHalo != node.halo.isEnabled {
                node.halo.isEnabled = showHalo
                if showHalo {
                    playBounce(on: node.sphere)
                } else {
                    node.sphere.stopAllAnimations(recursive: false)
                    node.sphere.transform.scale = .one
                }
            }
            
            // Update position and enable state
            node.sphere.isEnabled = seat.isAvailable || isSelected
            node.sphere.position.z = isSelected ? OrbMaterials.sphereRadius * 0.25 : 0
        }
    }
    
    
    private var loadingOverlay: some View {
        ProgressView()
            .controlSize(.large)
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    
    private func preloadResources(for space: SpaceData) async {
        // Load map image first
        if let urlString = space.mapURL, let url = URL(string: urlString) {
            _ = try? await URLSession.shared.data(from: url)
        }
        
        // Prime RealityKit resources
        await SpaceMapResources.prime(for: space)
        
        // Small delay to ensure smooth transition
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
    

    /// Creates the map background view (Image or Gradient)
    private func mapBackground(urlString: String?) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: mapDisplayWidth, height: mapDisplayHeight, alignment: .center)
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default: // Handles failure
                        errorMapBackground
                    }
                }
            } else {
                defaultMapBackground
            }
        }
        .frame(width: mapDisplayWidth, height: mapDisplayHeight)
        .clipped()
    }

    /// Default gradient background
    private var defaultMapBackground: some View {
         LinearGradient(gradient: Gradient(colors: [.indigo.opacity(0.2), .purple.opacity(0.2)]), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Background shown on image load error
    private var errorMapBackground: some View {
         Rectangle().fill(Color.gray.opacity(0.2))
             .overlay(Text("Failed to load map image").foregroundColor(.secondary))
    }

    /// Displays the label of the selected seat below the map
    @ViewBuilder
    private func selectedSeatLabel(seats: [SeatPosition]) -> some View {
        // Find the selected seat object using currentSeatId
        let selectedSeat = seats.first { $0.id == currentSeatId }

        // Display label or placeholder text
        let labelText = selectedSeat?.label ?? (currentSeatId == nil ? "No seat selected" : "Seat \(currentSeatId!)") // Fallback logic
        let fontStyle: Font = (selectedSeat != nil) ? .title2 : .title3
        let foregroundColor: Color = (selectedSeat != nil) ? .primary : .secondary

        Text(labelText)
            .font(.title)
            .fontWeight(.semibold)
            .foregroundColor(foregroundColor)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
            .shadow(radius: 3)
            .frame(minHeight: 50)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.easeInOut, value: currentSeatId)
            .id(currentSeatId ?? "no_seat")
    }


    /// Creates the horizontal scrollable list of seat buttons
    private func seatPicker(seats: [SeatPosition]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select a seat:")
                .font(.headline)
                .padding(.leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(seats.sorted(by: { ($0.label ?? $0.id) < ($1.label ?? $1.id) })) { seat in
                        let isSelected = currentSeatId == seat.id
                        let isDisabled = !seat.isAvailable && !isSelected

                        Button {
                            selectSeat(seatId: isSelected ? nil : seat.id)
                        } label: {
                            HStack {
                                Text(seat.label ?? "ID: \(seat.id)")
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(SeatButtonStyle(isSelected: isSelected))
                        .disabled(isDisabled)
                        .opacity(isDisabled ? 0.4 : 1.0)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        .shadow(radius: 6)
        .frame(maxWidth: mapDisplayWidth * 0.95)
    }

    /// View to display when an error occurs during loading
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again") {
                loadData() // Re-trigger loading
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    /// View to display when there's no map data or no seats
    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "map.fill")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No Seat Map Available")
                 .font(.title2)
                 .padding(.top)

            if appModel.selectedSpace == nil {
                Text("Please select a space first.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else if appModel.selectedSpace?.seats?.isEmpty ?? true {
                 Text("This space currently has no seats configured.")
                     .font(.callout)
                     .foregroundColor(.secondary)
            }
        }
        .padding()
    }


    // MARK: - Logic Functions

    /// Syncs the local `currentSeatId` from the AppModel.
    private func syncSelectedSeatFromModel() {
        currentSeatId = appModel.selectedSpace?.currentSeat ?? "seat_1"
        print("🔄 Initial sync: Local currentSeatId set to \(currentSeatId ?? "nil") from model.")
    }

    /// Simulates loading data (replace with actual async fetch).
    private func loadData() {
        print("⏳ Starting data load task...")
        errorMessage = nil
        isLoading = true

        // Launch a background task to do heavy lifting without blocking the UI
        Task {
            // --- This simulates your actual data loading/validation ---
            // It runs on a background thread.
            try? await Task.sleep(for: .seconds(1))

            let spaceExists = appModel.selectedSpace != nil
            let seatsExist = !(appModel.selectedSpace?.seats?.isEmpty ?? true)
            var finalErrorMessage: String? = nil
            // --- End Simulation ---

            if !spaceExists {
                finalErrorMessage = "No space selected"
            } else if !seatsExist {
                print("⚠️ No seats found for the selected space.")
            } else {
                print("✅ Seats loaded for space.")
            }
            
            // Now, switch back to the main actor to safely update the UI
            await MainActor.run {
                self.errorMessage = finalErrorMessage
                syncSelectedSeatFromModel()
                self.previousSeatId = self.currentSeatId
                self.isLoading = false // Hide loading indicator
                print("✅ Loading complete. UI updated.")
            }
        }
    }

    /// Handles the tap action originating from the RealityView gesture or picker button.
    private func handleTap(on seat: SeatPosition) {
        if currentSeatId == seat.id {
            // If tapping the already selected seat, deselect it
            print("ℹ️ [Tap Action] Deselecting seat: \(seat.id)")
            selectSeat(seatId: nil) // Pass nil to deselect
        } else if seat.isAvailable {
            // If tapping an available, unselected seat, select it
            print("🎯 [Tap Action] Selecting available seat: \(seat.id)")
            selectSeat(seatId: seat.id)
        } else {
            // If tapping an unavailable seat, do nothing (or provide feedback)
            print("🚫 [Tap Action] Tapped unavailable seat: \(seat.id)")
            // TODO: Add feedback like a slight shake?
        }
    }

    /// Central function to update the selected seat state (local and model).
    private func selectSeat(seatId: String?) { // Accepts optional String for deselection
        // 1. Prevent redundant updates
        guard seatId != currentSeatId else {
            print("ℹ️ [SelectSeat] Attempted selection change to '\(seatId ?? "nil")', which is already current. No action needed.")
            return
        }

        // 2. Validate availability if selecting (not deselecting)
        if let newSeatId = seatId { // Only check if selecting a specific seat
            guard let seat = appModel.selectedSpace?.seats?.first(where: { $0.id == newSeatId }),
                  seat.isAvailable else {
                print("🚫 [SelectSeat] Cannot select unavailable seat \(newSeatId).")
                return // Exit if seat not found or unavailable
            }
            print("✅ [SelectSeat] Preparing to select seat: \(newSeatId)")
        } else {
            print("✅ [SelectSeat] Preparing to deselect.")
        }
        
        // 3. --- FIX IS HERE ---
        //    Capture the outgoing ID before changing it. This is the key.
        previousSeatId = currentSeatId

        // 4. Update local state FIRST for immediate UI feedback (picker, label)
        //    The RealityView's update closure will now react to this change.
        currentSeatId = seatId
        print("➡️ [SelectSeat] Local state changed. Previous: '\(previousSeatId ?? "nil")', Current: '\(currentSeatId ?? "nil")'.")

        // 5. Update the central AppModel state
        appModel.updateSelectedSpaceSeat(to: seatId ?? "seat_1")
        print("➡️ [SelectSeat] AppModel notified of selection change to: \(seatId ?? "nil")")
    }

    /// Plays the bounce animation on the specified sphere entity.
    private func playBounce(on sphere: ModelEntity) {
        print("▶️ Animating orb bounce for \(sphere.name)")

        sphere.stopAllAnimations(recursive: false)

        guard let parent = sphere.parent else {
            print("⚠️ Cannot animate bounce: Sphere \(sphere.name) has no parent.")
            return
        }
        
        let currentTransform = sphere.transform // Relative to parent

        var upTransform = currentTransform
        upTransform.scale = SIMD3<Float>(repeating: OrbMaterials.overshoot)

        var downTransform = currentTransform
        downTransform.scale = SIMD3<Float>(repeating: OrbMaterials.undershoot)

        var endTransform = currentTransform
        endTransform.scale = .one

        // Chain the animations
        sphere.move(to: upTransform, relativeTo: parent, duration: OrbMaterials.durUp, timingFunction: .easeOut)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbMaterials.durUp) {
            sphere.move(to: downTransform, relativeTo: parent, duration: OrbMaterials.durDn, timingFunction: .easeInOut)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + OrbMaterials.durDn) {
                sphere.move(to: endTransform, relativeTo: parent, duration: OrbMaterials.durSet, timingFunction: .easeIn)
            }
        }
    }

}
