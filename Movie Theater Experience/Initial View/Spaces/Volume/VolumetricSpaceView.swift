import SwiftUI
import RealityKit
import Combine

/// A view that displays a single volumetric space with controls for entering immersive mode
struct VolumetricSpaceView: View {
    // MARK: - Properties
    let space: SpaceData
    let onEnter: () -> Void
    @StateObject private var viewModel = VolumetricSpaceViewModel()
    
    // Environment access for immersive spaces
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(AppModel.self) private var appModel
    
    // State for UI controls
    @State private var scale: Float = 0.2
    @State private var rotationAngle: Angle = .zero
    @State private var showControls = true
    @State private var showJoinFailedAlert = false
    
    // Timer for continuous rotation
    let rotationTimer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // 3D content
            if let entity = viewModel.entity {
                // Reality view with the 3D model
                ZStack {
                    RealityView { content in
                        content.add(entity)
                        
                        // Apply initial transform
                        entity.scale = SIMD3<Float>(repeating: scale)
                    } update: { content in
                        if let entity = content.entities.first {
                            // Update scale
                            entity.scale = SIMD3<Float>(repeating: scale)
                            
                            // Update rotation around Y axis
                            entity.orientation = simd_quatf(
                                angle: Float(rotationAngle.radians),
                                axis: SIMD3<Float>(0, 1, 0)
                            )
                        }
                    }
                    .gesture(
                        // Magnification gesture for scaling
                        MagnifyGesture()
                            .onChanged { value in
                                let delta = Float(value.magnification - 1.0)
                                scale = max(0.05, scale + delta * 0.1)
                            }
                    )
                    .gesture(
                        // Drag gesture for manual rotation
                        DragGesture()
                            .onChanged { value in
                                let sensitivity: Double = 0.01
                                rotationAngle += Angle(degrees: value.translation.width * sensitivity)
                            }
                    )
                    .onReceive(rotationTimer) { _ in
                        // Auto-rotation (slow)
                        if viewModel.autoRotate {
                            rotationAngle += Angle(degrees: 0.1)
                            if rotationAngle >= Angle(degrees: 360) {
                                rotationAngle = .zero
                            }
                        }
                    }
                }
                
                // Overlay controls
                if showControls {
                    overlayControls
                }
            } else if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error: error)
            }
        }
        .frame(minHeight: 300)
        .background(Material.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 4)
        .onAppear {
            viewModel.loadSpace(space)
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .alert("Could Not Join Space", isPresented: $showJoinFailedAlert) {
            Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please go to the Settings app and set a username before joining a shared space.")
        }
    }
    
    // MARK: - Subviews
    
    /// Overlay controls for the 3D view
    private var overlayControls: some View {
        VStack {
            // Top row with title and toggle controls
            HStack {
                Text(space.spaceName)
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                
                Spacer()
                
                // Auto-rotate toggle
                Button(action: {
                    viewModel.autoRotate.toggle()
                }) {
                    Image(systemName: viewModel.autoRotate ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                
                // Reset view button
                Button(action: resetView) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
            .padding([.top, .horizontal])
            
            Spacer()
            
            // Enter immersive space button
            Button(action: enterImmersiveSpace) {
                HStack {
                    Image(systemName: "visionpro")
                    Text("Enter Space")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(width: 240)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
            
            // Scale controls
            HStack {
                Button(action: { decreaseScale() }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
                
                Slider(value: Binding(
                    get: { Double(scale) },
                    set: { scale = Float($0) }
                ), in: 0.05...1.0)
                .frame(width: 150)
                
                Button(action: { increaseScale() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(15)
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
        }
    }
    
    /// Loading state view
    private var loadingView: some View {
        VStack(spacing: 15) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading \(space.spaceName)...")
                .font(.headline)
            Text("Please wait while we prepare your experience")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// Error state view
    private func errorView(error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Unable to Load Space")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error.localizedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundColor(.secondary)
            
            Button("Try Again") {
                viewModel.loadSpace(space)
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
    
    // MARK: - Actions
    
    /// Reset the view to default settings
    private func resetView() {
        scale = 0.2  // Default scale
        rotationAngle = .zero
    }
    
    /// Decrease the model scale
    private func decreaseScale() {
        scale = max(0.05, scale - 0.05)
    }
    
    /// Increase the model scale
    private func increaseScale() {
        scale = min(1.0, scale + 0.05)
    }
    
    private func enterImmersiveSpace() {
        // 1. Ask the ViewModel if we are allowed to enter.
        if viewModel.canEnterSpace() {
            // 2. If YES: Proceed with setting up the models and calling onEnter.
            print("🚀 View is proceeding to enter space.")
            
            // This is your existing setup logic
            appModel.selectedSpace = space
            if let entity = viewModel.entity {
                SpacesEntityWrapper.shared.setEntity(entity.clone(recursive: true))
                SpacesEntityWrapper.shared.setSpaceEntity(entity.clone(recursive: true))
                SpacesEntityWrapper.shared.setActiveSceneEntity(entity.clone(recursive: true))
                print("✅ Entity set in shared wrapper.")
            }
            
            onEnter() // This triggers the immersive transition
            
        } else {
            // 3. If NO: Show the alert. The immersive transition is never started.
            showJoinFailedAlert = true
        }
    }
}
