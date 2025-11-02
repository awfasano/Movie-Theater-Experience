//
//  SpaceDrawingRenderer.swift
//  Movie Theater Experience
//
//  Created by GPT-5 Codex on 3/16/25.
//

import Foundation
import RealityKit
import SwiftUI
import simd
#if os(visionOS)
import UIKit
#else
import AppKit
#endif

@MainActor
final class SpaceDrawingRenderer {
    enum PreviewShape {
        case sphere
        case square
    }

    private weak var rootAnchor: Entity?
    private let strokeContainer = Entity()
    private var volumeGuide: Entity?
    private var materialCache: [MaterialKey: PhysicallyBasedMaterial] = [:]
    private var strokeEntities: [String: Entity] = [:]
    private var strokeSignatures: [String: StrokeSignature] = [:]
    private var fingerPreviewEntity: ModelEntity?
    private let circleSegmentCount = 14
    
    private struct StrokeTipTrail {
        let entity: ModelEntity
        let angle: Float
        let radialAmplitude: Float
        let longitudinalRange: Float
        let speed: Float
        let phase: Float
    }
    
    private struct StrokeTipEffect {
        let root: Entity
        let glow: ModelEntity
        let spark: ModelEntity
        let light: PointLight
        let trails: [StrokeTipTrail]
        let baseColor: UIColor
    }
    
    private final class StrokeAnimation {
        let stroke: SpaceStroke
        var progress: Float
        let isLocal: Bool
        var task: Task<Void, Never>?
        var currentEntity: Entity?
        var tipEffect: StrokeTipEffect?
        let createdAt: Date
        
        init(stroke: SpaceStroke, isLocal: Bool) {
            self.stroke = stroke
            self.isLocal = isLocal
            self.progress = 0
            self.createdAt = Date()
        }
    }
    
    private var strokeAnimations: [String: StrokeAnimation] = [:]
    
    private struct MaterialKey: Hashable {
        let color: SIMD4<Float>
        let metallic: Float
        let roughness: Float
        let emission: Float
        let emissionColor: SIMD4<Float>
    }
    
    private struct StrokeSignature: Equatable {
        let updatedAt: TimeInterval
        let pointCount: Int
        let color: SIMD4<Float>
        let width: Double
        let metallic: Double
        let roughness: Double
        let emission: Double
        let emissionColor: SIMD4<Float>
        let style: String
    }
    
    func attach(to entity: Entity) {
        if rootAnchor !== entity {
            strokeContainer.removeFromParent()
            volumeGuide?.removeFromParent()
            entity.addChild(strokeContainer)
            rootAnchor = entity
        }
        ensureVolumeGuide()
    }
    
    func setVisibility(_ isVisible: Bool) {
        // Strokes remain visible regardless of overlay state; guide mirrors overlay visibility.
        volumeGuide?.isEnabled = isVisible
    }
    
    func clear() {
        cancelAllAnimations()
        strokeEntities.values.forEach { $0.removeFromParent() }
        strokeEntities.removeAll()
        strokeSignatures.removeAll()
        strokeContainer.children.removeAll()
        materialCache.removeAll()
    }
    
    func render(strokes: [SpaceStroke]) {
        guard rootAnchor != nil else {
            print("⚠️ Renderer render called without anchor")
            return
        }
        
        let activeStrokes = strokes.filter { !$0.isDeleted && !$0.isEraser }
        let activeIds = Set(activeStrokes.map { $0.strokeId })
        
        // Remove stale stroke entities
        let staleIds = strokeEntities.keys.filter { !activeIds.contains($0) }
        for id in staleIds {
            if let animation = strokeAnimations[id] {
                animation.task?.cancel()
                animation.currentEntity?.removeFromParent()
                animation.tipEffect?.root.removeFromParent()
                animation.tipEffect = nil
                strokeAnimations.removeValue(forKey: id)
            }
            strokeEntities[id]?.removeFromParent()
            strokeEntities.removeValue(forKey: id)
            strokeSignatures.removeValue(forKey: id)
        }

        // Update or create entities for active strokes
        for stroke in activeStrokes {
            if let animation = strokeAnimations[stroke.strokeId], animation.progress < 1 {
                continue
            }
            let signature = makeSignature(for: stroke)
            
            if strokeSignatures[stroke.strokeId] != signature {
                strokeEntities[stroke.strokeId]?.removeFromParent()
                guard let entity = buildStrokeEntity(for: stroke) else {
                    strokeEntities.removeValue(forKey: stroke.strokeId)
                    strokeSignatures.removeValue(forKey: stroke.strokeId)
                    continue
                }
                strokeContainer.addChild(entity)
                strokeEntities[stroke.strokeId] = entity
                strokeSignatures[stroke.strokeId] = signature
            } else if strokeEntities[stroke.strokeId]?.parent == nil, let entity = strokeEntities[stroke.strokeId] {
                strokeContainer.addChild(entity)
            }
        }
    }
    
    func updateFingerPreview(color: Color,
                             emission: Double,
                             emissiveColor: Color? = nil,
                             width: Double,
                             worldPosition: SIMD3<Float>,
                             isVisible: Bool,
                             shape: PreviewShape = .sphere) {
        guard let anchor = rootAnchor else { return }
        let entity = ensureFingerPreviewEntity(on: anchor)
        let localPosition = anchor.convert(position: worldPosition, from: nil)
        entity.position = localPosition
        entity.isEnabled = isVisible

        let diameter = max(Float(width), 0.0015)
        let mesh: MeshResource
        switch shape {
        case .sphere:
            mesh = MeshResource.generateSphere(radius: max(diameter * 0.5, 0.001))
        case .square:
            mesh = MeshResource.generateBox(width: diameter, height: diameter, depth: max(diameter * 0.15, 0.001))
        }
        var material = UnlitMaterial()
        let components = color.rgbaComponents
        let emissive = CGFloat(max(0, min(emission, 1)))
        let lerp: (CGFloat) -> Double = { channel in
            let value = channel + (1 - channel) * emissive
            return Double(min(max(value, 0), 1))
        }
        let blended = Color(
            red: lerp(components.r),
            green: lerp(components.g),
            blue: lerp(components.b),
            opacity: Double(min(1, components.a + emissive * 0.2))
        )
        let emissiveTint = emissiveColor ?? color
        let baseComponents = blended.rgbaComponents
        let emissiveComponents = emissiveTint.rgbaComponents
        let mix = CGFloat(max(0, min(emission, 1)))
        let finalColor = Color(
            red: Double(baseComponents.r + (emissiveComponents.r - baseComponents.r) * mix),
            green: Double(baseComponents.g + (emissiveComponents.g - baseComponents.g) * mix),
            blue: Double(baseComponents.b + (emissiveComponents.b - baseComponents.b) * mix),
            opacity: Double(baseComponents.a)
        )
        material.color = .init(tint: UIColor(finalColor).withAlphaComponent(0.9))
        entity.model = ModelComponent(mesh: mesh, materials: [material])
        if shape == .square {
            entity.orientation = simd_quatf()
        }
    }
    
    func hideFingerPreview() {
        fingerPreviewEntity?.isEnabled = false
    }

    func cancelAllAnimations() {
        for (id, animation) in strokeAnimations {
            animation.task?.cancel()
            animation.currentEntity?.removeFromParent()
            animation.tipEffect?.root.removeFromParent()
            animation.tipEffect = nil
            strokeEntities.removeValue(forKey: id)
            strokeSignatures.removeValue(forKey: id)
        }
        strokeAnimations.removeAll()
    }

    func animateStroke(_ stroke: SpaceStroke, isLocalUser: Bool) {
        guard let _ = rootAnchor else { return }
        guard stroke.points.count > 1 else { return }
        if let existingEntity = strokeEntities[stroke.strokeId] {
            existingEntity.removeFromParent()
            strokeEntities.removeValue(forKey: stroke.strokeId)
            strokeSignatures.removeValue(forKey: stroke.strokeId)
        }
        if let existing = strokeAnimations[stroke.strokeId] {
            existing.task?.cancel()
            existing.currentEntity?.removeFromParent()
            existing.tipEffect?.root.removeFromParent()
            existing.tipEffect = nil
            strokeAnimations.removeValue(forKey: stroke.strokeId)
        }
        let animation = StrokeAnimation(stroke: stroke, isLocal: isLocalUser)
        strokeAnimations[stroke.strokeId] = animation
        startAnimation(for: stroke.strokeId)
    }

    private func startAnimation(for strokeId: String) {
        guard let animation = strokeAnimations[strokeId] else { return }
        updateAnimatedStroke(strokeId: strokeId, progress: 0.02)
        let baseDuration: Double = animation.isLocal ? 0.35 : 0.8
        let perSegment: Double = 0.012
        let extra = Double(max(0, animation.stroke.points.count - 20)) * perSegment
        let duration = min(2.2, baseDuration + extra)
        let steps = max(16, animation.stroke.points.count * 2)
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            for step in 1...steps {
                if Task.isCancelled { return }
                let progress = min(1, Float(step) / Float(steps))
                let interval = duration / Double(steps)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                await MainActor.run {
                    self.updateAnimatedStroke(strokeId: strokeId, progress: progress)
                }
            }
            await MainActor.run {
                self.finishAnimation(strokeId: strokeId)
            }
        }
        animation.task = task
    }

    private func updateAnimatedStroke(strokeId: String, progress: Float) {
        guard let animation = strokeAnimations[strokeId] else { return }
        animation.progress = progress
        animation.currentEntity?.removeFromParent()
        if let previous = strokeEntities.removeValue(forKey: strokeId) {
            previous.removeFromParent()
        }
        let partialStroke = trimmedStroke(animation.stroke, progress: progress)
        guard let entity = buildStrokeEntity(for: partialStroke) else { return }
        strokeContainer.addChild(entity)
        animation.currentEntity = entity
        strokeEntities[strokeId] = entity
        strokeSignatures[strokeId] = makeSignature(for: animation.stroke)
        let radius = max(Float(animation.stroke.width) * 0.5, 0.001)
        if progress < 0.995, let tip = partialStroke.points.last?.simdVector {
            let previous = partialStroke.points.dropLast().last?.simdVector
            updateTipEffect(for: animation,
                            tipWorldPosition: tip,
                            previousWorldPosition: previous,
                            radius: radius,
                            progress: progress)
        } else {
            removeTipEffect(for: animation)
        }
    }

    private func finishAnimation(strokeId: String) {
        guard let animation = strokeAnimations[strokeId] else { return }
        animation.task?.cancel()
        animation.task = nil
        updateAnimatedStroke(strokeId: strokeId, progress: 1)
        strokeAnimations.removeValue(forKey: strokeId)
    }

    private func updateTipEffect(for animation: StrokeAnimation,
                                 tipWorldPosition: SIMD3<Float>,
                                 previousWorldPosition: SIMD3<Float>?,
                                 radius: Float,
                                 progress: Float) {
        guard rootAnchor != nil else { return }
        let effect = ensureTipEffect(for: animation, radius: radius)
        let localTip = strokeContainer.convert(position: tipWorldPosition, from: nil)
        effect.root.position = localTip
        var forward = SIMD3<Float>(0, 1, 0)
        if let previous = previousWorldPosition {
            let localPrevious = strokeContainer.convert(position: previous, from: nil)
            let direction = simd_normalize(localTip - localPrevious)
            if simd_length(direction) > .leastNonzeroMagnitude {
                forward = direction
                let lookTarget = localTip + direction
                effect.root.look(at: lookTarget, from: localTip, relativeTo: nil)
            }
        } else if let parent = effect.root.parent {
            let column = parent.transform.matrix.columns.1
            forward = SIMD3<Float>(column.x, column.y, column.z)
        }
        if simd_length_squared(forward) < 1e-5 {
            forward = SIMD3<Float>(0, 1, 0)
        }
        let forwardUnit = simd_normalize(forward)
        let basis = makeOrthonormalBasis(forward: forwardUnit, previousUp: nil)
        let elapsed = Float(Date().timeIntervalSince(animation.createdAt))
        let pulse = max(0.75, 1 + 0.35 * sin(elapsed * 6.5))
        let fade = max(0.2, 1 - progress * 0.9)
        let rootScale = SIMD3<Float>(repeating: pulse * fade + 0.65)
        effect.root.scale = rootScale
        effect.spark.scale = SIMD3<Float>(repeating: max(0.35, rootScale.x * 0.7))
        effect.light.light.intensity = 900 * Float(fade + 0.35)
        updateTipMaterials(effect: effect,
                           glowAlpha: CGFloat(0.45 + Double(fade) * 0.45),
                           coreAlpha: CGFloat(0.35 + Double(fade) * 0.4))
        
        for trail in effect.trails {
            let time = fmodf(elapsed * trail.speed + trail.phase, 1)
            let falloff = max(0, 1 - time)
            let radialVector = cos(trail.angle) * basis.right + sin(trail.angle) * basis.up
            let radialOffset = radialVector * trail.radialAmplitude * falloff
            let longitudinal = -forwardUnit * trail.longitudinalRange * time
            trail.entity.position = radialOffset + longitudinal
            let scaleValue = max(0.08, falloff * fade) * 0.6
            trail.entity.scale = SIMD3<Float>(repeating: scaleValue)
            updateTrailMaterial(trail.entity,
                                baseColor: effect.baseColor,
                                alpha: CGFloat(0.2 + Double(falloff * fade) * 0.55))
        }
    }
    
    private func ensureTipEffect(for animation: StrokeAnimation, radius: Float) -> StrokeTipEffect {
        if let existing = animation.tipEffect {
            if existing.root.parent !== strokeContainer {
                existing.root.removeFromParent()
                strokeContainer.addChild(existing.root)
            }
            return existing
        }
        let created = makeTipEffect(for: animation.stroke, radius: radius)
        strokeContainer.addChild(created.root)
        animation.tipEffect = created
        return created
    }
    
    private func removeTipEffect(for animation: StrokeAnimation) {
        animation.tipEffect?.root.removeFromParent()
        animation.tipEffect = nil
    }
    
    private func makeTipEffect(for stroke: SpaceStroke, radius: Float) -> StrokeTipEffect {
        let root = Entity()
        root.name = "StrokeTip-\(stroke.strokeId)"
        let glowRadius = max(radius * 2.4, 0.004)
        let coreRadius = max(radius * 1.2, 0.002)
        let color = UIColor(stroke.emissionColor)
        
        let glowMesh = MeshResource.generateSphere(radius: glowRadius)
        var glowMaterial = UnlitMaterial()
        glowMaterial.color = .init(tint: color.withAlphaComponent(0.7))
        let glow = ModelEntity(mesh: glowMesh, materials: [glowMaterial])
        glow.name = "StrokeTipGlow"
        root.addChild(glow)
        
        let sparkMesh = MeshResource.generateSphere(radius: coreRadius)
        var sparkMaterial = UnlitMaterial()
        sparkMaterial.color = .init(tint: UIColor.white.withAlphaComponent(0.8))
        let spark = ModelEntity(mesh: sparkMesh, materials: [sparkMaterial])
        spark.name = "StrokeTipCore"
        root.addChild(spark)

        var trails: [StrokeTipTrail] = []
        let trailMesh = MeshResource.generateSphere(radius: max(coreRadius * 0.7, 0.0012))
        for index in 0..<5 {
            let trailEntity = ModelEntity(mesh: trailMesh, materials: [sparkMaterial])
            trailEntity.name = "StrokeTipTrail-\(index)"
            trailEntity.scale = SIMD3<Float>(repeating: 0.4)
            root.addChild(trailEntity)
            let angleSeed = pseudoRandom(for: stroke.strokeId, index: index + 101)
            let angle = angleSeed * Float.pi * 2
            let radialSeed = pseudoRandom(for: stroke.strokeId, index: index + 211)
            let radialAmplitude = max(radius * (0.35 + radialSeed * 0.55), 0.003)
            let longitudinalSeed = pseudoRandom(for: stroke.strokeId, index: index + 317)
            let longitudinalRange = max(radius * (2.4 + longitudinalSeed * 3.4), 0.015)
            let speedSeed = pseudoRandom(for: stroke.strokeId, index: index + 419)
            let speed = 0.8 + speedSeed * 1.1
            let phase = pseudoRandom(for: stroke.strokeId, index: index + 523)
            trails.append(StrokeTipTrail(entity: trailEntity,
                                         angle: angle,
                                         radialAmplitude: radialAmplitude,
                                         longitudinalRange: longitudinalRange,
                                         speed: speed,
                                         phase: phase))
        }
        
        let light = PointLight()
        light.light.intensity = 800
        light.light.attenuationRadius = max(radius * 90, 0.25)
        light.light.color = color
        light.name = "StrokeTipLight"
        root.addChild(light)
        
        return StrokeTipEffect(root: root, glow: glow, spark: spark, light: light, trails: trails, baseColor: color)
    }
    
    private func updateTipMaterials(effect: StrokeTipEffect, glowAlpha: CGFloat, coreAlpha: CGFloat) {
        if var glowModel = effect.glow.model {
            glowModel.materials = glowModel.materials.map { material in
                guard var unlit = material as? UnlitMaterial else { return material }
                unlit.color = .init(tint: effect.baseColor.withAlphaComponent(glowAlpha))
                return unlit
            }
            effect.glow.model = glowModel
        }
        if var sparkModel = effect.spark.model {
            sparkModel.materials = sparkModel.materials.map { material in
                guard var unlit = material as? UnlitMaterial else { return material }
                unlit.color = .init(tint: UIColor.white.withAlphaComponent(coreAlpha))
                return unlit
            }
            effect.spark.model = sparkModel
        }
    }

    private func updateTrailMaterial(_ entity: ModelEntity, baseColor: UIColor, alpha: CGFloat) {
        guard var model = entity.model else { return }
        model.materials = model.materials.map { material in
            guard var unlit = material as? UnlitMaterial else { return material }
            unlit.color = .init(tint: baseColor.withAlphaComponent(alpha))
            return unlit
        }
        entity.model = model
    }
    
    private func trimmedStroke(_ stroke: SpaceStroke, progress: Float) -> SpaceStroke {
        let clampedProgress = max(0.0001, min(progress, 1))
        guard clampedProgress < 1, stroke.points.count > 1 else { return stroke }
        let total = stroke.points.count
        let rawIndex = Float(total - 1) * clampedProgress
        let lower = Int(floor(rawIndex))
        let upper = min(total - 1, lower + 1)
        let t = rawIndex - Float(lower)
        var newPoints = Array(stroke.points[0...lower])
        if upper > lower {
            let start = stroke.points[lower].simdVector
            let end = stroke.points[upper].simdVector
            let interpolated = start + (end - start) * t
            newPoints.append(SpaceDrawingPoint3D(position: interpolated, timestamp: nil))
        }
        return strokeCopy(stroke, replacingPointsWith: newPoints)
    }

    private func strokeCopy(_ stroke: SpaceStroke, replacingPointsWith points: [SpaceDrawingPoint3D]) -> SpaceStroke {
        SpaceStroke(
            id: stroke.id,
            strokeId: stroke.strokeId,
            spaceId: stroke.spaceId,
            userId: stroke.userId,
            userName: stroke.userName,
            colorHex: stroke.colorHex,
            width: stroke.width,
            isEraser: stroke.isEraser,
            metallic: stroke.metallic,
            roughness: stroke.roughness,
            createdAt: stroke.createdAt,
            updatedAt: stroke.updatedAt,
            points: points,
            isDeleted: stroke.isDeleted,
            emission: stroke.emission,
            style: stroke.style,
            emissionColorHex: stroke.emissionColorHex
        )
    }
    
    func detach() {
        cancelAllAnimations()
        clear()
        strokeContainer.removeFromParent()
        volumeGuide?.removeFromParent()
        volumeGuide = nil
        fingerPreviewEntity?.removeFromParent()
        fingerPreviewEntity = nil
        rootAnchor = nil
    }
    
    // MARK: - Build Geometry
    
    private func buildStrokeEntity(for stroke: SpaceStroke) -> Entity? {
        guard let anchor = rootAnchor else { return nil }
        var points = stroke.points.map { anchor.convert(position: $0.simdVector, from: nil) }
        guard !points.isEmpty else { return nil }
        let radius = max(Float(stroke.width) * 0.5, 0.001)
        points = prepareStrokePoints(points, radius: radius, style: stroke.style)
        let lapIterations = stroke.style == .classicCylinder ? 1 : 2
        let lapFactor: Float = stroke.style == .classicCylinder ? 0.25 : 0.4
        points = laplacianSmooth(points, iterations: lapIterations, smoothingFactor: lapFactor)
        guard let first = points.first else { return nil }
        let strokeMaterial = material(for: stroke)

        if points.count == 1 {
            return makeSinglePointEntity(style: stroke.style,
                                         point: first,
                                         radius: radius,
                                         material: strokeMaterial,
                                         anchor: anchor,
                                         strokeId: stroke.strokeId)
        }
        
        switch stroke.style {
        case .tubular:
            guard let mesh = makeTubularMesh(points: points, radius: radius) else { return nil }
            let entity = ModelEntity(mesh: mesh, materials: [strokeMaterial])
            entity.name = "Stroke-\(stroke.strokeId)"
            return entity
        case .flat:
            guard let mesh = makeFlatMesh(points: points,
                                          halfWidth: radius * 1.4,
                                          normal: flatNormal(for: anchor)) else { return nil }
            let entity = ModelEntity(mesh: mesh, materials: [strokeMaterial])
            entity.name = "Stroke-\(stroke.strokeId)"
            return entity
        case .ribbon:
            guard let mesh = makeRibbonMesh(points: points,
                                            baseRadius: radius,
                                            strokeId: stroke.strokeId,
                                            normal: flatNormal(for: anchor)) else { return nil }
            let entity = ModelEntity(mesh: mesh, materials: [strokeMaterial])
            entity.name = "Stroke-\(stroke.strokeId)"
            return entity
        case .classicCylinder:
            return makeClassicCylinderEntity(points: points,
                                             radius: radius,
                                             stroke: stroke,
                                             material: strokeMaterial)
        case .box:
            let halfWidth = radius * 1.45
            let halfHeight = radius * 0.65
            return makeBoxStrokeEntity(points: points,
                                       halfWidth: halfWidth,
                                       halfHeight: halfHeight,
                                       material: strokeMaterial,
                                       strokeId: stroke.strokeId)
        }
    }
    
    private func material(for stroke: SpaceStroke) -> PhysicallyBasedMaterial {
        let color = stroke.color
        let rgba = color.rgbaComponents
        let emissiveColor = stroke.emissionColor
        let emissiveRGBA = emissiveColor.rgbaComponents
        let emissiveStrength = Float(
            max(
                SpaceDrawingConstants.emissiveRange.lowerBound,
                min(SpaceDrawingConstants.emissiveRange.upperBound, stroke.emission)
            )
        )
        let key = MaterialKey(
            color: SIMD4<Float>(Float(rgba.r), Float(rgba.g), Float(rgba.b), Float(rgba.a)),
            metallic: Float(stroke.metallic),
            roughness: Float(stroke.roughness),
            emission: emissiveStrength,
            emissionColor: SIMD4<Float>(Float(emissiveRGBA.r), Float(emissiveRGBA.g), Float(emissiveRGBA.b), Float(emissiveRGBA.a))
        )

        if let cached = materialCache[key] {
            return cached
        }

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(color))
        material.metallic = .init(floatLiteral: key.metallic.clamped(to: 0...1))
        material.roughness = .init(floatLiteral: key.roughness.clamped(to: Float(SpaceDrawingConstants.roughnessRange.lowerBound)...Float(SpaceDrawingConstants.roughnessRange.upperBound)))
        if emissiveStrength > 0 {
            let clamped = max(0, min(emissiveStrength, 1))
            material.emissiveIntensity = clamped
            material.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: UIColor(emissiveColor))
        }
        materialCache[key] = material
        return material
    }
    
    private func makeSignature(for stroke: SpaceStroke) -> StrokeSignature {
        let rgba = stroke.color.rgbaComponents
        let emissionRGBA = stroke.emissionColor.rgbaComponents
        return StrokeSignature(
            updatedAt: stroke.updatedAt.timeIntervalSinceReferenceDate,
            pointCount: stroke.points.count,
            color: SIMD4<Float>(Float(rgba.r), Float(rgba.g), Float(rgba.b), Float(rgba.a)),
            width: stroke.width,
            metallic: stroke.metallic,
            roughness: stroke.roughness,
            emission: stroke.emission,
            emissionColor: SIMD4<Float>(Float(emissionRGBA.r), Float(emissionRGBA.g), Float(emissionRGBA.b), Float(emissionRGBA.a)),
            style: stroke.style.rawValue
        )
    }
    
    private func ensureVolumeGuide() {
        guard let anchor = rootAnchor else { return }
        if volumeGuide == nil {
            volumeGuide = makeWireframeCube(size: SpaceDrawingConstants.volumeSizeMeters, color: .white.withAlphaComponent(0.35))
            volumeGuide?.name = "SpaceDrawingVolumeGuide"
            volumeGuide?.isEnabled = false
        }
        guard let guide = volumeGuide else { return }
        if guide.parent !== anchor {
            guide.removeFromParent()
            anchor.addChild(guide, preservingWorldTransform: false)
            print("🧊 Volume guide attached: size=\(SpaceDrawingConstants.volumeSizeMeters)")
        }
    }
    
    private func ensureFingerPreviewEntity(on anchor: Entity) -> ModelEntity {
        if let entity = fingerPreviewEntity {
            if entity.parent !== anchor {
                entity.removeFromParent()
                anchor.addChild(entity)
            }
            return entity
        }
        
        let mesh = MeshResource.generateSphere(radius: 0.0015)
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor.white.withAlphaComponent(0.85))
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "FingerPreview"
        anchor.addChild(entity)
        fingerPreviewEntity = entity
        return entity
    }
    
    private func makeSinglePointEntity(style: SpaceStroke.Style,
                                       point: SIMD3<Float>,
                                       radius: Float,
                                       material: PhysicallyBasedMaterial,
                                       anchor: Entity,
                                       strokeId: String) -> Entity? {
        switch style {
        case .flat, .ribbon:
            let plane = MeshResource.generatePlane(width: radius * 2.4, depth: radius * 2.4)
            let entity = ModelEntity(mesh: plane, materials: [material])
            let desiredNormal = flatNormal(for: anchor)
            let planeNormal = SIMD3<Float>(0, 1, 0)
            var orientation = simd_quatf(from: planeNormal, to: simd_normalize(desiredNormal))
            if !isFinite(orientation) {
                orientation = simd_quatf()
            }
            entity.orientation = orientation
            entity.position = point
            entity.name = "Stroke-\(strokeId)"
            return entity
        case .tubular, .classicCylinder, .box:
            let sphere = MeshResource.generateSphere(radius: radius)
            let entity = ModelEntity(mesh: sphere, materials: [material])
            entity.position = point
            entity.name = "Stroke-\(strokeId)"
            return entity
        }
    }
    
    private func prepareStrokePoints(_ points: [SIMD3<Float>],
                                     radius: Float,
                                     style: SpaceStroke.Style) -> [SIMD3<Float>] {
        guard points.count >= 2 else { return points }
        let smoothingPasses = style == .classicCylinder ? 0 : 2
        var processed = smoothPoints(points, passes: smoothingPasses)
        let targetSpacing = max(radius * (style == .classicCylinder ? 1.3 : 1.0), 0.008)
        processed = densifyPoints(processed, maxSegmentLength: targetSpacing)
        return processed
    }
    
    private func makeTubularMesh(points: [SIMD3<Float>], radius: Float) -> MeshResource? {
        guard points.count >= 2 else { return nil }
        
        var descriptor = MeshDescriptor()
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texCoords: [SIMD2<Float>] = []
        let ringCount = circleSegmentCount
        let vStep = 1.0 / Float(points.count - 1)
        
        positions.reserveCapacity(points.count * ringCount)
        normals.reserveCapacity(points.count * ringCount)
        texCoords.reserveCapacity(points.count * ringCount)
        
        var previousUp: SIMD3<Float>? = nil
        
        for (index, point) in points.enumerated() {
            let prev = index == 0 ? point : points[index - 1]
            let next = index == points.count - 1 ? point : points[index + 1]
            
            var tangent = next - prev
            let tangentLength = simd_length(tangent)
            if tangentLength < 1e-5 {
                tangent = SIMD3<Float>(0, 1, 0)
            } else {
                tangent /= tangentLength
            }
            
            let frame = makeOrthonormalBasis(forward: tangent, previousUp: previousUp)
            let right = frame.right
            let up = frame.up
            previousUp = up
            
            for segment in 0..<ringCount {
                let angle = (Float(segment) / Float(ringCount)) * Float.pi * 2
                let offset = cos(angle) * right * radius + sin(angle) * up * radius
                positions.append(point + offset)
                normals.append(simd_normalize(offset))
                texCoords.append(SIMD2<Float>(Float(segment) / Float(ringCount), Float(index) * vStep))
            }
        }
        
        var indices: [UInt32] = []
        indices.reserveCapacity((points.count - 1) * ringCount * 6)
        
        for ring in 0..<(points.count - 1) {
            let base = ring * ringCount
            let nextBase = (ring + 1) * ringCount
            
            for segment in 0..<ringCount {
                let current = base + segment
                let next = base + (segment + 1) % ringCount
                let upper = nextBase + segment
                let upperNext = nextBase + (segment + 1) % ringCount
                
                indices.append(UInt32(current))
                indices.append(UInt32(next))
                indices.append(UInt32(upper))
                
                indices.append(UInt32(next))
                indices.append(UInt32(upperNext))
                indices.append(UInt32(upper))
            }
        }
        
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(texCoords)
        descriptor.primitives = .triangles(indices)
        
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            print("⚠️ Failed to generate stroke mesh: \(error)")
            return nil
        }
    }
    
    private func makeFlatMesh(points: [SIMD3<Float>],
                              halfWidth: Float,
                              normal: SIMD3<Float>) -> MeshResource? {
        guard points.count >= 2 else { return nil }
        var descriptor = MeshDescriptor()
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texCoords: [SIMD2<Float>] = []
        
        let normalizedNormal = simd_normalize(normal)
        
        for (index, point) in points.enumerated() {
            let prev = index == 0 ? point : points[index - 1]
            let next = index == points.count - 1 ? point : points[index + 1]
            var tangent = next - prev
            if simd_length_squared(tangent) < 1e-8 {
                tangent = SIMD3<Float>(0, 0, 1)
            }
            tangent = simd_normalize(tangent)
            var right = simd_cross(normalizedNormal, tangent)
            if simd_length_squared(right) < 1e-8 {
                right = SIMD3<Float>(1, 0, 0)
            }
            right = simd_normalize(right)
            
            positions.append(point + right * halfWidth)
            positions.append(point - right * halfWidth)
            normals.append(normalizedNormal)
            normals.append(normalizedNormal)
            
            let v = Float(index) / Float(points.count - 1)
            texCoords.append(SIMD2<Float>(0, v))
            texCoords.append(SIMD2<Float>(1, v))
        }
        
        var indices: [UInt32] = []
        for ring in 0..<(points.count - 1) {
            let base = ring * 2
            let nextBase = base + 2
            indices.append(UInt32(base))
            indices.append(UInt32(base + 1))
            indices.append(UInt32(nextBase))
            indices.append(UInt32(base + 1))
            indices.append(UInt32(nextBase + 1))
            indices.append(UInt32(nextBase))
        }
        
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(texCoords)
        descriptor.primitives = .triangles(indices)
        
        return try? MeshResource.generate(from: [descriptor])
    }
    
    private func makeRibbonMesh(points: [SIMD3<Float>],
                                baseRadius: Float,
                                strokeId: String,
                                normal: SIMD3<Float>) -> MeshResource? {
        guard points.count >= 2 else { return nil }
        
        var descriptor = MeshDescriptor()
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texCoords: [SIMD2<Float>] = []
        let normalizedNormal = simd_normalize(normal)
        
        for (index, point) in points.enumerated() {
            let prev = index == 0 ? point : points[index - 1]
            let next = index == points.count - 1 ? point : points[index + 1]
            var tangent = next - prev
            if simd_length_squared(tangent) < 1e-8 {
                tangent = SIMD3<Float>(0, 0, 1)
            }
            tangent = simd_normalize(tangent)
            
            var right = simd_cross(normalizedNormal, tangent)
            if simd_length_squared(right) < 1e-8 {
                right = SIMD3<Float>(1, 0, 0)
            }
            right = simd_normalize(right)
            var up = simd_normalize(simd_cross(tangent, right))
            
            let jitter = pseudoRandom(for: strokeId, index: index)
            let widthMultiplier = 0.75 + 0.35 * sin(Float(index) * 0.6 + jitter * Float.pi * 2)
            let twist = (jitter - 0.5) * 0.35
            let cosTwist = cos(twist)
            let sinTwist = sin(twist)
            let twistedRight = right * cosTwist + up * sinTwist
            up = simd_normalize(simd_cross(tangent, twistedRight))
            let halfWidth = baseRadius * 1.8 * widthMultiplier
            
            positions.append(point + twistedRight * halfWidth)
            positions.append(point - twistedRight * halfWidth)
            normals.append(up)
            normals.append(up)
            
            let v = Float(index) / Float(points.count - 1)
            texCoords.append(SIMD2<Float>(0, v))
            texCoords.append(SIMD2<Float>(1, v))
        }
        
        var indices: [UInt32] = []
        for ring in 0..<(points.count - 1) {
            let base = ring * 2
            let nextBase = base + 2
            indices.append(UInt32(base))
            indices.append(UInt32(base + 1))
            indices.append(UInt32(nextBase))
            indices.append(UInt32(base + 1))
            indices.append(UInt32(nextBase + 1))
            indices.append(UInt32(nextBase))
        }
        
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(texCoords)
        descriptor.primitives = .triangles(indices)
        
        return try? MeshResource.generate(from: [descriptor])
    }
    
    private func makeClassicCylinderEntity(points: [SIMD3<Float>],
                                           radius: Float,
                                           stroke: SpaceStroke,
                                           material: PhysicallyBasedMaterial) -> Entity? {
        let parent = Entity()
        parent.name = "Stroke-\(stroke.strokeId)"

        if let first = points.first {
            let startCap = ModelEntity(mesh: MeshResource.generateSphere(radius: radius * 1.05), materials: [material])
            startCap.position = first
            parent.addChild(startCap)
        }

        for (index, end) in points.enumerated() where index > 0 {
            let start = points[index - 1]
            var direction = end - start
            let length = simd_length(direction)
            guard length > 0.0003 else { continue }
            direction /= length
            let mesh = MeshResource.generateCylinder(height: length + radius * 0.4, radius: radius * 0.98)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = (start + end) / 2
            let up = SIMD3<Float>(0, 1, 0)
            var axis = direction
            if simd_length_squared(axis) < 1e-8 {
                axis = SIMD3<Float>(0, 0, 1)
            }
            entity.orientation = simd_quatf(from: up, to: simd_normalize(axis))
            parent.addChild(entity)

            if index > 1 {
                let jointSphere = ModelEntity(mesh: MeshResource.generateSphere(radius: radius * 1.02), materials: [material])
                jointSphere.position = start
                parent.addChild(jointSphere)
            }
        }
        
        if let last = points.last {
            let endCap = ModelEntity(mesh: MeshResource.generateSphere(radius: radius * 1.05), materials: [material])
            endCap.position = last
            parent.addChild(endCap)
        }

        return parent.children.isEmpty ? nil : parent
    }

    private func makeBoxStrokeEntity(points: [SIMD3<Float>],
                                     halfWidth: Float,
                                     halfHeight: Float,
                                     material: PhysicallyBasedMaterial,
                                     strokeId: String) -> Entity? {
        guard let first = points.first else { return nil }
        let parent = Entity()
        parent.name = "Stroke-\(strokeId)"

        let capSize = SIMD3<Float>(halfWidth * 2, halfHeight * 2, min(halfWidth, halfHeight) * 1.8)
        let capMesh = MeshResource.generateBox(size: capSize)

        func addCap(at position: SIMD3<Float>) {
            let cap = ModelEntity(mesh: capMesh, materials: [material])
            cap.position = position
            parent.addChild(cap)
        }

        if points.count == 1 {
            addCap(at: first)
            return parent
        }

        addCap(at: first)

        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            var direction = end - start
            let length = simd_length(direction)
            guard length > 0.0003 else { continue }
            direction /= length
            let depth = max(length + min(halfWidth, halfHeight) * 0.6, 0.001)
            let boxSize = SIMD3<Float>(halfWidth * 2, halfHeight * 2, depth)
            let mesh = MeshResource.generateBox(size: boxSize)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = (start + end) / 2
            let forward = SIMD3<Float>(0, 0, 1)
            entity.orientation = simd_quatf(from: forward, to: simd_normalize(direction))
            parent.addChild(entity)
            addCap(at: end)
        }

        return parent
    }
    
    private func flatNormal(for _: Entity) -> SIMD3<Float> {
        SIMD3<Float>(0, 0, 1)
    }
    
    private func pseudoRandom(for seed: String, index: Int) -> Float {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        hash ^= UInt64(index & 0xFFFF)
        hash &*= 0x100000001b3
        return Float(hash % 1000) / 1000.0
    }
    
    private func smoothPoints(_ points: [SIMD3<Float>], passes: Int) -> [SIMD3<Float>] {
        guard passes > 0, points.count >= 3 else { return points }
        var current = points
        for _ in 0..<passes {
            var smoothed: [SIMD3<Float>] = [current.first!]
            for i in 1..<current.count - 1 {
                let blended = (current[i - 1] * 0.25 + current[i] * 0.5 + current[i + 1] * 0.25)
                smoothed.append(blended)
            }
            smoothed.append(current.last!)
            current = smoothed
        }
        return current
    }
    
    private func densifyPoints(_ points: [SIMD3<Float>], maxSegmentLength: Float) -> [SIMD3<Float>] {
        guard points.count >= 2 else { return points }
        let threshold = max(maxSegmentLength, 0.005)
        var result: [SIMD3<Float>] = []

        for i in 0..<(points.count - 1) {
            let start = points[i]
            let end = points[i + 1]
            if result.isEmpty {
                result.append(start)
            }
            let delta = end - start
            let length = simd_length(delta)
            if length <= threshold || length.isZero {
                result.append(end)
                continue
            }
            let steps = max(1, Int(ceil(length / threshold)))
            for step in 1...steps {
                let t = Float(step) / Float(steps)
                result.append(start + delta * t)
            }
        }
        return result
    }
    
    private func laplacianSmooth(_ points: [SIMD3<Float>], iterations: Int, smoothingFactor: Float) -> [SIMD3<Float>] {
        guard points.count > 2, iterations > 0 else { return points }
        var current = points
        let factor = max(0, min(smoothingFactor, 0.5))
        for _ in 0..<iterations {
            var smoothed = current
            for i in 1..<current.count - 1 {
                let previous = current[i - 1]
                let next = current[i + 1]
                let average = (previous + next) / 2
                let delta = average - current[i]
                smoothed[i] = current[i] + delta * factor
            }
            current = smoothed
        }
        return current
    }
    
    private func makeOrthonormalBasis(forward: SIMD3<Float>, previousUp: SIMD3<Float>?) -> (right: SIMD3<Float>, up: SIMD3<Float>) {
        var provisionalUp = previousUp ?? SIMD3<Float>(0, 1, 0)
        var right = simd_cross(provisionalUp, forward)
        if simd_length_squared(right) < 1e-6 {
            provisionalUp = SIMD3<Float>(1, 0, 0)
            right = simd_cross(provisionalUp, forward)
        }
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(forward, right))
        return (right, up)
    }
    
    private func isFinite(_ quaternion: simd_quatf) -> Bool {
        let v = quaternion.vector
        return v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite
    }
    
    private func makeWireframeCube(size: SIMD3<Float>, color: UIColor) -> Entity {
        let entity = Entity()
        let halfSize = size / 2
        let vertices: [SIMD3<Float>] = [
            SIMD3(-halfSize.x, -halfSize.y, -halfSize.z), SIMD3(halfSize.x, -halfSize.y, -halfSize.z),
            SIMD3(halfSize.x, halfSize.y, -halfSize.z), SIMD3(-halfSize.x, halfSize.y, -halfSize.z),
            SIMD3(-halfSize.x, -halfSize.y, halfSize.z), SIMD3(halfSize.x, -halfSize.y, halfSize.z),
            SIMD3(halfSize.x, halfSize.y, halfSize.z), SIMD3(-halfSize.x, halfSize.y, halfSize.z)
        ]
        let edges: [(Int, Int)] = [
            (0,1),(1,2),(2,3),(3,0),
            (4,5),(5,6),(6,7),(7,4),
            (0,4),(1,5),(2,6),(3,7)
        ]
        let swiftUIColor = Color(color)
        edges.forEach { startIndex, endIndex in
            let start = vertices[startIndex]
            let end = vertices[endIndex]
            let length = simd_distance(start, end)
            let midPoint = (start + end) / 2
            let cylinder = MeshResource.generateCylinder(height: length, radius: 0.01)
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor(swiftUIColor))
            let edgeEntity = ModelEntity(mesh: cylinder, materials: [material])
            edgeEntity.position = midPoint
            edgeEntity.look(at: end, from: start, relativeTo: nil)
            entity.addChild(edgeEntity)
        }
        return entity
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Color {
    var rgbaComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        #if os(visionOS)
        typealias NativeColor = UIColor
        #else
        typealias NativeColor = NSColor
        #endif
        let native = NativeColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        native.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }
}
