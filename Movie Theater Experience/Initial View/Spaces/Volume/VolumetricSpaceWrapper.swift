import Foundation
import SwiftUICore
import SwiftUI
import _RealityKit_SwiftUI
import Combine

struct VolumetricSpaceWrapper: View {
    let space: SpaceData
    @State private var entity: Entity?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var scale: Float = 0.2  // Start with a much smaller scale
    @State private var rotationAngle: Angle = .zero
    @State private var currentUserCount: Int  // Track current user count
    @State private var maxUserCount: Int      // Track max user count
    
    // Access environment for immersive space
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    // Use the shared SpaceService instance
    private let spaceService = SpaceService.shared
    
    // Timer for continuous rotation
    let rotationTimer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    
    // Initialize with space data
    init(space: SpaceData) {
        self.space = space
        self._currentUserCount = State(initialValue: space.currentUserCount)
        self._maxUserCount = State(initialValue: space.maxUserCount)
    }
    
    var body: some View {
        ZStack {
            if let entity = entity {
                // Entity view with controls overlay
                ZStack {
                    // The 3D model view
                    RealityView { content in
                        content.add(entity)
                        
                        // Apply initial scale and rotation to the entity
                        entity.scale = SIMD3<Float>(repeating: scale)
                    } update: { content in
                        if let entity = content.entities.first {
                            // Update scale
                            entity.scale = SIMD3<Float>(repeating: scale)
                            
                            // Update rotation - rotate around Y axis
                            entity.orientation = simd_quatf(angle: Float(rotationAngle.radians), axis: SIMD3<Float>(0, 1, 0))
                        }
                    }
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                // Update scale based on magnification
                                let delta = Float(value.magnification - 1.0)
                                scale = max(0.01, scale + delta * 0.1) // Smaller increments
                            }
                    )
                    .onReceive(rotationTimer) { _ in
                        // Update rotation angle for slow continuous rotation
                        rotationAngle += Angle(degrees: 0.1)
                        if rotationAngle >= Angle(degrees: 360) {
                            rotationAngle = .zero
                        }
                    }
                }
                
                // Always visible controls (positioned with overlay instead of ZStack)
                VStack {
                    // Top row with user count and reset button
                    HStack {
                        // User count indicator with occupancy status
                        HStack(spacing: 4) {
                            Circle()
                                .fill(occupancyColor)
                                .frame(width: 8, height: 8)
                            
                            Text("\(currentUserCount)/\(maxUserCount) users")
                                .font(.callout)
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        Button(action: {
                            resetView()
                        }) {
                            Text("Reset View")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    
                    Spacer()
                    
                    // Enter Space button in the center
                    Button(action: {
                        enterImmersiveSpace()
                    }) {
                        HStack {
                            Image(systemName: "globe")
                            Text("Enter Space")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(width: 200)
                        .background(LinearGradient(
                            colors: [Color.blue, Color.purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                    
                    // Scale controls at the bottom
                    HStack {
                        Button(action: {
                            scale = max(0.01, scale - 0.05)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        
                        Slider(value: Binding(
                            get: { Double(scale) },
                            set: { scale = Float($0) }
                        ), in: 0.01...2.0)
                        .frame(width: 150)
                        .tint(.white)
                        
                        Button(action: {
                            scale = min(2.0, scale + 0.05)
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    .padding(.bottom, 20)
                    .padding(.horizontal, 20)
                }
            } else if isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text("Loading volumetric content...")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadError != nil {
                errorView
            }
        }
        .background(Material.regularMaterial)
        .onAppear {
            loadEntity()
            
            // Set up listener for user count updates
            setupUserCountListener()
        }
        .onDisappear {
            // Clean up listener when view disappears
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
        }
    }
    
    // Computed property for occupancy color
    private var occupancyColor: Color {
        let percentage = Float(currentUserCount) / Float(max(1, maxUserCount))
        switch percentage {
        case ..<0.5:
            return .green // Low occupancy
        case ..<0.8:
            return .yellow // Medium occupancy
        default:
            return .red // High occupancy
        }
    }
    
    // Set up listener for user count updates
    private func setupUserCountListener() {
        guard let spaceId = space.id else { return }
        
        // Create a publisher for space updates
        let userCountPublisher = spaceService.getSpaceUpdates(for: spaceId)
        
        userCountPublisher
            .receive(on: RunLoop.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    print("Error in user count listener: \(error)")
                }
            } receiveValue: { updatedSpace in
                self.currentUserCount = updatedSpace.currentUserCount
                self.maxUserCount = updatedSpace.maxUserCount
            }
            .store(in: &cancellables)
    }
    
    // Reset the view to default settings
    private func resetView() {
        scale = 0.2  // Reset to a reasonable default scale
        rotationAngle = .zero
    }
    
    // Function to enter immersive space
    private func enterImmersiveSpace() {
        // Make sure the current space is set in the app model
        appModel.selectedSpace = space
        
        // Open the immersive space
        Task {
            // Open your immersive space with the ID from your app model
            await openImmersiveSpace(id: appModel.spacesID)
        }
    }
    
    // User-friendly error view
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Unable to Load Space")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("We couldn't load this content right now. Please try again later.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundColor(.secondary)
            
            Button("Try Again") {
                loadEntity()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
        .padding(30)
        .background(Material.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Load entity using SpaceService instead of direct download
    private func loadEntity() {
        isLoading = true
        loadError = nil
        entity = nil
        
        print("🔄 Loading entity for: \(space.spaceName)")
        
        // Use our shared SpaceService instead of direct download
        spaceService.loadSpace(from: space) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let loadedEntity):
                    print("✅ Entity loaded successfully via SpaceService")
                    
                    // Store the full entity for later use in immersive space
                    TheatreEntityWrapper.shared.setSpaceEntity(loadedEntity)
                    
                    // Create a container entity for proper transformation
                    let containerEntity = Entity()
                    
                    // Find and use only the intro entity if it exists
                    if let introEntityName = self.space.introEntityName, !introEntityName.isEmpty {
                        print("🔍 Looking for intro entity named: \(introEntityName)")
                        if let introEntity = self.findEntityRecursively(named: introEntityName, in: loadedEntity) {
                            print("✅ Found intro entity: \(introEntityName)")
                            
                            // Create a clone of the intro entity
                            let clonedIntro = introEntity.clone(recursive: true)
                            
                            // Calculate the center of the intro entity
                            let bounds = clonedIntro.visualBounds(relativeTo: nil)
                            let center = SIMD3<Float>(
                                (bounds.min.x + bounds.max.x) / 2,
                                (bounds.min.y + bounds.max.y) / 2,
                                (bounds.min.z + bounds.max.z) / 2
                            )
                            
                            // Adjust the position to center the intro entity at origin
                            clonedIntro.position = -center
                            
                            // Add the centered intro entity to the container
                            containerEntity.addChild(clonedIntro)
                            
                            print("🔄 Centered intro entity at origin. Original center: \(center)")
                        } else {
                            print("⚠️ Intro entity not found, using full model")
                            
                            // Center the full model at origin
                            let bounds = loadedEntity.visualBounds(relativeTo: nil)
                            let center = SIMD3<Float>(
                                (bounds.min.x + bounds.max.x) / 2,
                                (bounds.min.y + bounds.max.y) / 2,
                                (bounds.min.z + bounds.max.z) / 2
                            )
                            
                            let clonedEntity = loadedEntity.clone(recursive: true)
                            clonedEntity.position = -center
                            containerEntity.addChild(clonedEntity)
                        }
                    } else {
                        print("ℹ️ No intro entity specified, using full model")
                        
                        // Center the full model at origin
                        let bounds = loadedEntity.visualBounds(relativeTo: nil)
                        let center = SIMD3<Float>(
                            (bounds.min.x + bounds.max.x) / 2,
                            (bounds.min.y + bounds.max.y) / 2,
                            (bounds.min.z + bounds.max.z) / 2
                        )
                        
                        let clonedEntity = loadedEntity.clone(recursive: true)
                        clonedEntity.position = -center
                        containerEntity.addChild(clonedEntity)
                    }
                    
                    // Use the container entity which has centered content
                    self.entity = containerEntity
                    self.isLoading = false
                    
                case .failure(let error):
                    print("⚠️ Entity loading error: \(error)")
                    self.isLoading = false
                    self.loadError = error
                }
            }
        }
    }
    
    // Helper function to find entities by name
    private func findEntityRecursively(named name: String, in entity: Entity) -> Entity? {
        if entity.name == name {
            return entity
        }
        
        for child in entity.children {
            if let found = findEntityRecursively(named: name, in: child) {
                return found
            }
        }
        
        return nil
    }
}
