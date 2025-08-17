import Foundation
import SwiftUI
import RealityKit
import RealityKitContent

struct WorldBuilderView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var immersiveSpaceManager: ImmersiveSpaceManager
    @EnvironmentObject private var windowManager: WindowManager
    @EnvironmentObject private var worldBuilder: WorldBuilderManager

    var body: some View {
        RealityView { content in
            // Setup the world builder scene
            await worldBuilder.setupScene(in: content)
        }
        // The 'update' closure has been removed as it was causing the errors and is not currently needed.
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Convert Point3D to SIMD3<Float>
                    let location = SIMD3<Float>(
                        Float(value.location3D.x),
                        Float(value.location3D.y),
                        Float(value.location3D.z)
                    )
                    worldBuilder.handleTap(on: value.entity, at: location)
                }
        )
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    // Convert Vector3D to SIMD3<Float>
                    let translation = SIMD3<Float>(
                        Float(value.translation3D.x),
                        Float(value.translation3D.y),
                        Float(value.translation3D.z)
                    )
                    worldBuilder.handleDrag(entity: value.entity, translation: translation)
                }
        )
        .onAppear {
            Task {
                await worldBuilder.initialize()
                // Connect to Gemini Live when ready
                await worldBuilder.connectVoiceInterface()
            }
        }
        .onDisappear {
            Task {
                await worldBuilder.cleanup()
            }
        }
    }
}

// MARK: - Helper Extensions for Type Conversion

extension SIMD3 where Scalar == Float {
    /// Convert from Point3D to SIMD3<Float>
    init(_ point: Point3D) {
        self.init(Float(point.x), Float(point.y), Float(point.z))
    }
    
    /// Convert from Vector3D to SIMD3<Float>
    init(_ vector: Vector3D) {
        self.init(Float(vector.x), Float(vector.y), Float(vector.z))
    }
}

extension Point3D {
    /// Convert from SIMD3<Float> to Point3D
    init(_ simd: SIMD3<Float>) {
        self.init(x: Double(simd.x), y: Double(simd.y), z: Double(simd.z))
    }
}

extension Vector3D {
    /// Convert from SIMD3<Float> to Vector3D
    init(_ simd: SIMD3<Float>) {
        self.init(x: Double(simd.x), y: Double(simd.y), z: Double(simd.z))
    }
}
