import SwiftUI // For Color, UIColor
import RealityKit

// MARK: - Reusable resources for SpaceMapView
/// Cached meshes & materials so we don’t recreate them every time the view appears


// MARK: - Materials and Constants
struct OrbMaterials {
    static let haloFactor: Float = 1.5   // halo is 1.4× sphere radius
    static let overshoot: Float = 1.4 // sphere pop scale
    static let undershoot: Float = 0.90
    static let durUp: TimeInterval = 0.25
    static let durDn: TimeInterval = 0.25
    static let durSet: TimeInterval = 0.3
    static let sphereRadius: Float = 0.01 // 2 cm radius

    static func halo() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .green.withAlphaComponent(0.10))
        m.roughness = 0.8
        m.blending = .transparent(opacity: 0.35)
        m.emissiveColor = .init(color: .green.withAlphaComponent(0.5))
        m.emissiveIntensity = 0.5
        return m
    }
    static func sel() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .green.withAlphaComponent(0.90))
        m.roughness = 0.2
        m.emissiveColor = .init(color: .green)
        m.emissiveIntensity = 0.8
        return m
    }
    static func ok() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.6, green: 0.6, blue: 0.9, alpha: 1))
        m.roughness = 0.3
        m.metallic = 0.8
        return m
    }
    static func off() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .gray.withAlphaComponent(0.80))
        m.roughness = 0.7
        m.metallic = 0.5
        return m
    }

    /// Generates the appropriate material for a sphere based on its state.
    static func sphereMaterial(for seat: SeatPosition, isSelected: Bool) -> PhysicallyBasedMaterial {
        isSelected ? Self.sel() : (seat.isAvailable ? Self.ok() : Self.off())
    }
}
