//
//  SeatOrbEntities.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 5/3/25.
//

import Foundation
import SwiftUICore
import RealityFoundation
import SwiftUI
import _RealityKit_SwiftUI

struct SeatOrbEntity: View {
    // MARK: ‑ Inputs
    let seat: SeatPosition
    let isSelected: Bool          // bound from parent view

    // MARK: ‑ Tunables
    private static let haloFactor: Float = 1.4   // halo is 1.4× sphere radius
    private static let overshoot  : Float = 1.25 // sphere pop scale
    private static let undershoot : Float = 0.90
    private static let durUp : TimeInterval = 0.18
    private static let durDn : TimeInterval = 0.18
    private static let durSet: TimeInterval = 0.24

    // MARK: ‑ Materials
    private struct M {
        static func halo() -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            m.baseColor        = .init(tint: .green.withAlphaComponent(0.10))
            m.roughness        = 0.8
            m.blending         = .transparent(opacity: 0.35)
            m.emissiveColor    = .init(color: .green.withAlphaComponent(0.5))
            m.emissiveIntensity = 0.5
            return m
        }
        static func sel () -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            m.baseColor        = .init(tint: .green.withAlphaComponent(0.90))
            m.roughness        = 0.2
            m.emissiveColor    = .init(color: .green)
            m.emissiveIntensity = 0.8
            return m
        }
        static func ok  () -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(red: 0.6, green: 0.6, blue: 0.9, alpha: 1))
            m.roughness = 0.3
            m.metallic  = 0.8
            return m
        }
        static func off () -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: .gray.withAlphaComponent(0.80))
            m.roughness = 0.7
            m.metallic  = 0.5
            return m
        }
    }
    private func sphereMaterial() -> PhysicallyBasedMaterial {
        isSelected ? M.sel() : (seat.isAvailable ? M.ok() : M.off())
    }

    // MARK: ‑ SwiftUI body
    var body: some View {
        RealityView { content in                   // ───── MAKE ─────
            let r: Float = 0.02                    // 2 cm radius

            // main sphere (becomes the animated entity)
            let sphere = ModelEntity(mesh: .generateSphere(radius: r),
                                     materials: [sphereMaterial()])
            sphere.name = seat.id
            sphere.components.set(
                CollisionComponent(shapes: [.generateSphere(radius: r)],
                                   mode: .trigger)
            )
            sphere.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            sphere.components.set(HoverEffectComponent())

            // halo child
            let halo = ModelEntity(mesh: .generateSphere(radius: r),
                                   materials: [M.halo()])
            halo.name            = "\(seat.id)-halo"
            halo.transform.scale = .init(repeating: Self.haloFactor)
            halo.isEnabled       = false
            sphere.addChild(halo)

            content.add(sphere)

        } update: { content in                     // ───── UPDATE ─────
            guard let sphere = content.entities.first(where: { $0.name == seat.id })
            else { return }

            // 1) refresh material
            if var mc = sphere.components[ModelComponent.self] {
                mc.materials = [sphereMaterial()]
                sphere.components.set(mc)
            }

            // 2) halo visibility & bounce
            guard let halo = sphere.findEntity(named: "\(seat.id)-halo") else { return }
            let haloVisible = halo.isEnabled

            if isSelected && !haloVisible {                 // became selected
                halo.isEnabled = true
                halo.stopAllAnimations(recursive: false)
                if let modelEntity = sphere as? ModelEntity {
                    playBounce(on: modelEntity)
                }

            } else if !isSelected && haloVisible {          // became deselected
                sphere.stopAllAnimations(recursive: false)
                halo.isEnabled = false
                sphere.transform.scale = .one               // reset
            }
        }
        .frame(width: 56, height: 56)
        .scaleEffect(isSelected ? 1.15 : 1.0)               // subtle 2‑D flair
        .animation(.smooth(duration: 0.20), value: isSelected)
    }

    // MARK: ‑ Animate the sphere (halo follows automatically)
    private func playBounce(on sphere: ModelEntity) {
        let up   = Transform(scale: .init(repeating: Self.overshoot))
        let down = Transform(scale: .init(repeating: Self.undershoot))
        let end  = Transform(scale: .one)

        sphere.move(to: up,   relativeTo: sphere,
                    duration: Self.durUp, timingFunction: .easeOut)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.durUp * 1_000_000_000))
            sphere.move(to: down, relativeTo: sphere,
                        duration: Self.durDn, timingFunction: .easeInOut)

            try? await Task.sleep(nanoseconds: UInt64(Self.durDn * 1_000_000_000))
            sphere.move(to: end,  relativeTo: sphere,
                        duration: Self.durSet, timingFunction: .easeIn)
        }
    }
}
