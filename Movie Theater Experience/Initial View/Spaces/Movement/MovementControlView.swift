import SwiftUI
import RealityKit
import ARKit // Import ARKit for hand tracking

struct MovementControlView: View {

    // MARK: - State Properties
    
    // ARKit session state
    @State private var session = ARKitSession()
    @State private var handTracking = HandTrackingProvider()
    
    // The sphere's 3D position, updated by hand tracking
    @State private var spherePosition = SIMD3<Float>.zero

    // MARK: - Constants
    
    private let boundary: Float = 0.1
    private let boxSize: Float = 0.2
    private let sphereRadius: Float = 0.02
    
    // MARK: - Body
    
    var body: some View {
        RealityView { content in
            // Create the bounding box with semi-transparency
            let boxMesh = MeshResource.generateBox(width: boxSize, height: boxSize, depth: boxSize)
            var boxMaterial = SimpleMaterial()
            boxMaterial.color = .init(tint: .blue.withAlphaComponent(0.3))
            let boxEntity = ModelEntity(mesh: boxMesh, materials: [boxMaterial])
            boxEntity.name = "boundingBox"
            content.add(boxEntity)
            
            // Create wireframe edges for the bounding box
            let wireframeEntity = createWireframeBox(size: boxSize)
            wireframeEntity.name = "wireframe"
            content.add(wireframeEntity)
            
            // Create the draggable sphere
            let sphereMesh = MeshResource.generateSphere(radius: sphereRadius)
            let sphereMaterial = SimpleMaterial(color: .white, roughness: 0.2, isMetallic: false)
            let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [sphereMaterial])
            sphereEntity.name = "controlSphere"
            
            // Add components for interaction feedback
            sphereEntity.components.set(InputTargetComponent())
            sphereEntity.components.set(HoverEffectComponent())
            
            content.add(sphereEntity)
            
        } update: { content in
            // This closure is called when spherePosition changes.
            // It finds the sphere and updates its position in the scene.
            if let sphere = content.entities.first(where: { $0.name == "controlSphere" }) {
                sphere.position = spherePosition
            }
        }
        .onAppear(perform: setupAndRunARKit)
        .task {
            // This asynchronous task runs in the background to process hand data.
            await processHandUpdates()
        }
    }
    
    // MARK: - ARKit Methods
    
    /// Configures and starts the ARKit session for hand tracking.
    private func setupAndRunARKit() {
        Task {
            do {
                // Request authorization to use hand tracking.
                let authorizations = await session.requestAuthorization(for: [.handTracking])
                
                // Safely check if the authorization for handTracking was granted.
                //if let handTrackingAuthorization = authorizations[.handTracking], handTrackingAuthorization == .granted {
                    // If granted, run the session with the hand tracking provider.
                 //   try await session.run([handTracking])
                //}
            } catch {
                print("Error: ARKit session failed to start.", error)
            }
        }
    }
    
    /// Continuously processes hand tracking updates from ARKit.
    private func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            guard let handAnchor = update.anchor as? HandAnchor,
                  handAnchor.chirality == .right, // We'll track the right hand
                  let indexFingerTip = handAnchor.handSkeleton?.joint(.indexFingerTip)
            else {
                continue
            }
            
            // Get the position of the joint in world space.
            let jointTransform = handAnchor.originFromAnchorTransform * indexFingerTip.anchorFromJointTransform
            
            // Extract the position vector from the transform matrix.
            let newPosition = SIMD3<Float>(
                jointTransform.columns.3.x,
                jointTransform.columns.3.y,
                jointTransform.columns.3.z
            )
            
            // Clamp the position to keep the sphere inside the bounding box.
            spherePosition.x = max(-boundary, min(boundary, newPosition.x))
            spherePosition.y = max(-boundary, min(boundary, newPosition.y))
            spherePosition.z = max(-boundary, min(boundary, newPosition.z))
        }
    }

    // MARK: - Helper Methods
    
    /// Creates a wireframe outline for the bounding box.
    private func createWireframeBox(size: Float) -> Entity {
        let wireframeParent = Entity()
        let halfSize = size / 2
        
        // Define the 8 vertices of the cube
        let vertices: [SIMD3<Float>] = [
            SIMD3(-halfSize, -halfSize, -halfSize), SIMD3( halfSize, -halfSize, -halfSize),
            SIMD3( halfSize,  halfSize, -halfSize), SIMD3(-halfSize,  halfSize, -halfSize),
            SIMD3(-halfSize, -halfSize,  halfSize), SIMD3( halfSize, -halfSize,  halfSize),
            SIMD3( halfSize,  halfSize,  halfSize), SIMD3(-halfSize,  halfSize,  halfSize)
        ]
        
        // Define the 12 edges of the cube
        let edges: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6),
            (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        
        // Create each edge as a thin cylinder
        for (start, end) in edges {
            let startPoint = vertices[start]
            let endPoint = vertices[end]
            let distance = simd_distance(startPoint, endPoint)
            let midPoint = (startPoint + endPoint) / 2
            
            let edgeMesh = MeshResource.generateCylinder(height: distance, radius: 0.002)
            let edgeMaterial = SimpleMaterial(color: .blue, isMetallic: false)
            let edgeEntity = ModelEntity(mesh: edgeMesh, materials: [edgeMaterial])
            
            edgeEntity.position = midPoint
            edgeEntity.look(at: endPoint, from: startPoint, relativeTo: nil)
            
            wireframeParent.addChild(edgeEntity)
        }
        
        return wireframeParent
    }
}


// MARK: - Preview
#Preview {
    MovementControlView()
}
