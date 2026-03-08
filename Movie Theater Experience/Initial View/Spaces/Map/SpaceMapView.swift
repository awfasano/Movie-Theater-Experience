import SwiftUI
import RealityKit
import RealityKitContent

// MARK: - Seat Map View (Main View Structure)
struct SpaceMapView: View {

    // MARK: ‑ Properties
    @Environment(AppModel.self) private var appModel // Access the shared app state

    // Local state for the view
    @State private var currentSeatId: String? = nil // Tracks the selected seat ID
    @State private var previousSeatId: String? = nil // Tracks the *last* selected ID for animation triggers
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var hoveredSeatId: String? = nil // <-- ADD THIS STATE


    // Map dimensions
    private let mapDisplayWidth: CGFloat = 1568
    private let mapDisplayHeight: CGFloat = 1024

    // MARK: - Body
    var body: some View {
        Group { // Use Group for conditional view structure
            if isLoading {
                ProgressView("Loading seat map…")
                    .onAppear(perform: loadData) // Trigger loading
            } else if let errorMessage {
                errorView(message: errorMessage) // Show error view
            } else if let space = appModel.selectedSpace, let seats = space.seats, !seats.isEmpty {
                renderMap(space: space, seats: seats) // Render the main map content
            } else {
                emptyView // Show empty state
            }
        }
        .onAppear {
            // Initial setup when view appears
            syncSelectedSeatFromModel()
            isLoading = appModel.selectedSpace?.seats == nil // Determine initial loading state
            if !isLoading {
                 DispatchQueue.main.async { isLoading = false } // Dismiss loading if already loaded
            }
            previousSeatId = currentSeatId // Initialize previous state
        }
        .onChange(of: appModel.selectedSpace?.id) { _, _ in
             // React to changes in the selected *space*
             syncSelectedSeatFromModel() // Reset local selection
             isLoading = true; errorMessage = nil // Reset loading/error
             loadData() // Reload data for the new space
             previousSeatId = currentSeatId // Update previous state after load
        }
        .onChange(of: appModel.selectedSpace?.currentSeat) { _, newModelSeatId in
             // React to changes in the *model's* selected seat
             if currentSeatId != newModelSeatId {
                 // Update local state ONLY if it differs from the model
                 currentSeatId = newModelSeatId
                 print("🔄 Synced local currentSeatId from model: \(newModelSeatId ?? "nil")")
                 // Don't update previousSeatId here; let the update closure handle changes
             }
         }
         .onChange(of: currentSeatId) { oldValue, newValue in
             // Track changes in the *local* state to correctly update previousSeatId
             // This ensures the RealityView update closure gets the correct 'before' state
             previousSeatId = oldValue
             print("ℹ️ Local currentSeatId changed. Previous: \(oldValue ?? "nil"), New: \(newValue ?? "nil")")
         }
    }

    // MARK: - View Builders / Subviews

    /// Builds the main map view with background and the single RealityView for orbs
    @ViewBuilder
    private func renderMap(space: SpaceData, seats: [SeatPosition]) -> some View {
        VStack(spacing: 12) { // Main container for map and picker
            ZStack { // Layering the background and the RealityView
                mapBackground(urlString: space.mapURL) // Background image/gradient

                // --- Single RealityView for ALL Orbs ---
                RealityView { content in // MAKE Closure: Creates initial entities
                    print("RealityView Make: Setting up scene for \(seats.count) seats.")
                    // Scale factor maps SwiftUI points (pixels) to RealityKit meters.
                    // Example: Make the RealityKit scene match the SwiftUI map width in meters (adjust as needed)
                    let sceneScale: Float = 1.0 / Float(mapDisplayWidth) // e.g., 1600 points = 1.0 meter
                    let worldWidth = Float(mapDisplayWidth) * sceneScale
                    let worldHeight = Float(mapDisplayHeight) * sceneScale

                    // Create an entity for each seat
                    for seat in seats {
                        // Create the main sphere
                        let sphere = ModelEntity(
                            mesh: .generateSphere(radius: OrbMaterials.sphereRadius),
                            materials: [OrbMaterials.sphereMaterial(for: seat, isSelected: false)] // Initial state: not selected
                        )
                        sphere.name = seat.id // Crucial for identification later
                        sphere.components.set(CollisionComponent(shapes: [.generateSphere(radius: OrbMaterials.sphereRadius)], mode: .trigger))
                        sphere.components.set(InputTargetComponent(allowedInputTypes: .indirect))
                        sphere.components.set(HoverEffectComponent())

                        // Calculate position in RealityKit space
                        // Map SwiftUI (0,0) top-left to RealityKit (-w/2, h/2, 0) center origin
                        let xPos = (Float(seat.position.x) - Float(mapDisplayWidth / 2.0)) * sceneScale
                        let yPos = (-Float(seat.position.y) + Float(mapDisplayHeight / 2.0)) * sceneScale // Invert Y
                        let zPos: Float = 0 // All spheres initially on the same Z plane

                        sphere.position = SIMD3<Float>(xPos, yPos, zPos)
                        // Create the halo as a child of the sphere
                        let halo = ModelEntity(
                            mesh: .generateSphere(radius: OrbMaterials.sphereRadius),
                            materials: [OrbMaterials.halo()]
                        )
                        halo.name = "\(seat.id)-halo" // Differentiate halo name
                        halo.transform.scale = .init(repeating: OrbMaterials.haloFactor)
                        halo.isEnabled = false // Start hidden
                        sphere.addChild(halo) // Attach halo to sphere

                        content.add(sphere) // Add the sphere (and its child halo) to the scene
                    }
                    print("RealityView Make: Finished creating entities.")

                } update: { content in // UPDATE Closure: Reacts to state changes
                    // Use the latest seat data from the model for updates
                    guard let currentSeats = appModel.selectedSpace?.seats else { return }

                    // Update each entity based on current state
                    for seat in currentSeats {
                        // Find the sphere entity using its name (seat.id)
                        guard let sphere = content.entities.first(where: { $0.name == seat.id }) as? ModelEntity else {
                            // print("RealityView Update: Warning - Could not find sphere entity for seat \(seat.id)")
                            continue // Skip if entity not found
                        }
                        // Find the corresponding halo entity
                        guard let halo = sphere.findEntity(named: "\(seat.id)-halo") else {
                            // print("RealityView Update: Warning - Could not find halo entity for seat \(seat.id)")
                            continue // Skip if halo not found
                        }

                        let isNowSelected = (currentSeatId == seat.id)
                        let wasSelected = (previousSeatId == seat.id) // Compare with the previous state

                        // 1. Update Sphere Material
                        // Inside RealityView -> update closure -> for loop

                        // 1. Update Sphere Material
                        // Inside RealityView -> update closure -> for loop

                        // 1. Update Sphere Material
                        if var modelComponent = sphere.components[ModelComponent.self] {
                            // Calculate the material that *should* be applied based on current state
                            let newMaterial = OrbMaterials.sphereMaterial(for: seat, isSelected: isNowSelected)

                            // --- FIX: Unconditionally set the material ---
                            // Since comparing materials directly is unreliable/unsupported,
                            // we just ensure the correct material is applied on every relevant update.
                            modelComponent.materials = [newMaterial]
                            sphere.components.set(modelComponent)
                            // --- End Fix ---
                        }


                        // 2. Update Halo Visibility & Trigger Animation
                        let haloShouldBeVisible = isNowSelected && seat.isAvailable // Show halo only if selected AND available
                        let haloIsVisible = halo.isEnabled

                        if haloShouldBeVisible && !haloIsVisible { // Condition: Became selected (and is available)
                            // print("RealityView Update: Orb \(seat.id) became selected. Enabling halo & bouncing.")
                            halo.isEnabled = true
                            playBounce(on: sphere) // Trigger the bounce animation

                        } else if !haloShouldBeVisible && haloIsVisible { // Condition: Became deselected (or unavailable)
                            // print("RealityView Update: Orb \(seat.id) deselected/unavailable. Disabling halo & resetting.")
                            sphere.stopAllAnimations(recursive: false) // Stop any ongoing bounce
                            halo.isEnabled = false
                            sphere.transform.scale = .one // Reset scale immediately
                        }

                        // 3. Update Entity Enablement (Visibility/Interactability)
                        // Disable the sphere entity entirely if it's unavailable and not selected
                        sphere.isEnabled = seat.isAvailable || isNowSelected

                        // 4. Visual Depth Adjustment (Optional)
                        // Slightly move selected orb forward for visual emphasis
                        let selectedZOffset: Float = OrbMaterials.sphereRadius * 0.25 // Small forward offset
                        sphere.position.z = isNowSelected ? selectedZOffset : 0.0
                    }
                    // Note: previousSeatId is now updated via .onChange(of: currentSeatId)
                }
                // --- Gestures attached to the RealityView ---
                .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                    // Handle taps directly on entities within the RealityView
                    print("RealityView Tap: Entity '\(value.entity.name)'")
                    var targetSeatId: String? = nil

                    // Check if the tapped entity is a sphere (name = seat.id)
                    if seats.contains(where: { $0.id == value.entity.name }) {
                        targetSeatId = value.entity.name
                    }
                    // Check if the tapped entity is a halo (parent name = seat.id)
                    else if let parentId = value.entity.parent?.name, seats.contains(where: { $0.id == parentId }) {
                        targetSeatId = parentId
                    }

                    // If we found a valid seat ID, process the tap
                    if let seatId = targetSeatId, let tappedSeat = seats.first(where: { $0.id == seatId }) {
                        handleTap(on: tappedSeat)
                    } else {
                         print("RealityView Tap: Warning - Tapped entity \(value.entity.name) does not correspond to a known seat.")
                    }
                })
                .frame(width: mapDisplayWidth, height: mapDisplayHeight) // Size the RealityView container
                .opacity(isLoading ? 0 : 1) // Fade in RealityView after loading
                .offset(z: -175)

            } // End ZStack containing background and RealityView
            .frame(width: mapDisplayWidth, height: mapDisplayHeight) // Set frame for the map area
            .clipShape(RoundedRectangle(cornerRadius: 12)) // Clip to rounded corners
            .shadow(radius: 8) // Add a subtle shadow

            // Display the label of the currently selected seat
            selectedSeatLabel(seats: seats)

            // Display the horizontal seat picker controls
            seatPicker(seats: seats)

        } // End main VStack
        .padding() // Add padding around the entire map + picker assembly
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
        currentSeatId = appModel.selectedSpace?.currentSeat
        print("🔄 Initial sync: Local currentSeatId set to \(currentSeatId ?? "nil") from model.")
    }

    /// Simulates loading data (replace with actual async fetch).
    private func loadData() {
        print("⏳ Loading data...")
        errorMessage = nil // Clear previous errors
        isLoading = true   // Show loading indicator

        // Simulate async work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // --- Replace with your actual data loading/validation ---
            let spaceExists = appModel.selectedSpace != nil
            let seatsExist = !(appModel.selectedSpace?.seats?.isEmpty ?? true)
            // --- End Simulation ---

            if !spaceExists {
                errorMessage = "No space selected"
            } else if !seatsExist {
                // Optionally set error or let emptyView handle it
                 print("⚠️ No seats found for the selected space.")
            } else {
                 print("✅ Seats loaded for space.")
            }

            // Ensure local seat state is synced *after* loading/validation
            syncSelectedSeatFromModel()
            previousSeatId = currentSeatId // Sync previous state after load/sync
            isLoading = false // Hide loading indicator
            print("✅ Loading complete. Current selected ID: \(currentSeatId ?? "nil")")
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

        // 3. Update local state FIRST for immediate UI feedback (picker, label)
        // The RealityView's update closure will react to this change.
        currentSeatId = seatId
        print("➡️ [SelectSeat] Local currentSeatId updated to: \(currentSeatId ?? "nil")")

        // 4. Update the central AppModel state
        // Ensure your AppModel's `updateSelectedSpaceSeat` can handle `nil`.
        // If not, you might need to pass a specific "deselected" identifier.
        appModel.updateSelectedSpaceSeat(to: seatId ?? "seat_1")
        print("➡️ [SelectSeat] AppModel notified of selection change to: \(seatId ?? "nil")")
    }

    /// Plays the bounce animation on the specified sphere entity.
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

        Task {
             do {
                 print("  🔼 Moving UP for \(sphere.name) to scale \(upTransform.scale)")
                 await sphere.move(to: upTransform, relativeTo: parent, duration: OrbMaterials.durUp, timingFunction: .easeOut)

                 print("  🔽 Moving DOWN for \(sphere.name) to scale \(downTransform.scale)")
                 await sphere.move(to: downTransform, relativeTo: parent, duration: OrbMaterials.durDn, timingFunction: .easeInOut)

                 print("  ⏹️ Moving END for \(sphere.name) to scale \(endTransform.scale)")
                 await sphere.move(to: endTransform, relativeTo: parent, duration: OrbMaterials.durSet, timingFunction: .easeIn)

                 print("✅ Bounce animation finished for \(sphere.name)")

             } catch is CancellationError {
                 print("⚠️ Bounce animation cancelled for \(sphere.name). Resetting transform.")
                 // FIX: Directly set the transform property for immediate reset
                 sphere.transform = endTransform

             } catch {
                 print("❌ Bounce animation failed unexpectedly for \(sphere.name): \(error). Resetting transform.")
                  // FIX: Directly set the transform property for immediate reset
                 sphere.transform = endTransform
             }
        }
    }

} // End struct SpaceMapView
