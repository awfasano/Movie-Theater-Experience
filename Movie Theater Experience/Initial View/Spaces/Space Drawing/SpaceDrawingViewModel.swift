//
//  SpaceDrawingViewModel.swift
//  Movie Theater Experience
//
//  Created by GPT-5 Codex on 3/16/25.
//

import Foundation
import SwiftUI
import RealityKit
import simd
import Combine

@MainActor
final class SpaceDrawingViewModel: ObservableObject {
    enum Tool: String {
        case brush
        case eraser
    }
    
    struct DraftStroke {
        var strokeId: String
        var brush: SpaceDrawingBrushOption
        var points: [SpaceDrawingPoint3D]
        var metallic: Double
        var roughness: Double
        var emissive: Double
        var createdAt: Date
    }
    
    // MARK: - Published State
    @Published private(set) var strokes: [SpaceStroke] = []
    @Published var isOverlayVisible = false {
        didSet { renderer.setVisibility(isOverlayVisible) }
    }
    @Published private(set) var strokesAreVisible = false
    @Published var selectedTool: Tool = .brush
    @Published var selectedBrush: SpaceDrawingBrushOption
    @Published var selectedColor: Color
    @Published var selectedWidth: Double
    @Published var selectedMetallic: Double
    @Published var selectedRoughness: Double
    @Published var selectedEmissive: Double
    @Published var selectedEmissiveColor: Color
    @Published var selectedDepth: Double = 0
    @Published var isDepthLocked = false
    @Published var lastError: String?

    var availableBrushes: [SpaceDrawingBrushOption] { SpaceDrawingConstants.defaultBrushes }
    var availableWidths: [Double] { SpaceDrawingConstants.availableLineWidths }
    var metallicRange: ClosedRange<Double> { SpaceDrawingConstants.metallicRange }
    var roughnessRange: ClosedRange<Double> { SpaceDrawingConstants.roughnessRange }
    var widthRange: ClosedRange<Double> {
        guard let min = availableWidths.min(), let max = availableWidths.max() else {
            return 0.002...0.02
        }
        return min...max
    }
    var emissiveRange: ClosedRange<Double> { SpaceDrawingConstants.emissiveRange }
    var depthRange: ClosedRange<Double> {
        let half = Double(SpaceDrawingConstants.volumeSizeMeters.z) / 2
        return -half...half
    }
    var canUndo: Bool { !strokes.isEmpty }
    
    // MARK: - Private Properties
    private let service: SpaceDrawingService
    private let renderer: SpaceDrawingRenderer
    private var cancellables = Set<AnyCancellable>()
    private var sceneRoot: Entity?
    private let drawingAnchor = Entity()
    private var currentSpaceId: String?
    private var draftStroke: DraftStroke?
    private var lastSampledPoint: SIMD3<Float>?
    private var isHandDrawing = false
    private let currentUserIdProvider: @MainActor () -> String
    private let usernameProvider: @MainActor () -> String
    private let handPoseProvider = SpaceDrawingHandPoseProvider()
    private let eraserRadius: Float = 0.05
    private var activeHand: SpaceDrawingHandPoseProvider.Sample.Hand?
    private var lastHandWorldPoint: SIMD3<Float>?
    private var knownStrokeIds = Set<String>()
    private var pendingAnimations: [SpaceStroke] = []
    
    @MainActor
    init(
        service: SpaceDrawingService = .shared,
        rendererFactory: @escaping @MainActor () -> SpaceDrawingRenderer = { SpaceDrawingRenderer() },
        currentUserIdProvider: @escaping @MainActor () -> String = { "" },
        usernameProvider: @escaping @MainActor () -> String = { "" }
    ) {
        self.service = service
        self.renderer = rendererFactory()
        self.currentUserIdProvider = currentUserIdProvider
        self.usernameProvider = usernameProvider
        
        let defaultBrush = SpaceDrawingConstants.defaultBrushes.first ?? SpaceDrawingBrushOption(
            id: "default",
            displayName: "Default",
            color: .white,
            width: 0.004,
            metallic: 0.1,
            roughness: 0.6,
            emissive: 0.0,
            style: .tubular,
            emissiveColorHex: nil
        )

        self.selectedBrush = defaultBrush
        self.selectedColor = defaultBrush.color
        self.selectedWidth = defaultBrush.width
        self.selectedMetallic = defaultBrush.metallic
        self.selectedRoughness = defaultBrush.roughness
        self.selectedEmissive = defaultBrush.emissive
        self.selectedDepth = 0
        self.selectedEmissiveColor = defaultBrush.emissiveColor ?? defaultBrush.color
        syncSelectedBrush()
        
        service.$strokes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] strokes in
                guard let self else { return }
                let newStrokes = strokes.filter { !self.knownStrokeIds.contains($0.strokeId) }
                self.strokes = strokes
                self.knownStrokeIds = Set(strokes.map { $0.strokeId })
                if self.drawingAnchor.parent != nil, self.strokesAreVisible {
                    let currentUser = self.currentUserIdProvider()
                    for stroke in newStrokes where stroke.userId != currentUser {
                        self.renderer.animateStroke(stroke, isLocalUser: false)
                    }
                } else {
                    let currentUser = self.currentUserIdProvider()
                    self.pendingAnimations.append(contentsOf: newStrokes.filter { $0.userId != currentUser })
                }
                self.displayCurrentStrokes(includePreview: false)
                self.adoptMaterialFromLatestStrokeIfNeeded()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Scene Integration
    func configureSceneRoot(_ entity: Entity) {
        sceneRoot = entity
        drawingAnchor.removeFromParent()
        drawingAnchor.transform = makeInitialAnchorTransform(relativeTo: entity)
        entity.addChild(drawingAnchor)
        print("📐 Drawing anchor configured at world position \(drawingAnchor.transform.translation)")
        renderer.attach(to: drawingAnchor)
        renderer.setVisibility(isOverlayVisible)
        renderer.render(strokes: strokesAreVisible ? strokes : [])
        triggerPendingAnimationsIfNeeded()
    }
    
    func activateSpace(_ space: SpaceData?) {
        guard let space, let id = space.id else {
            currentSpaceId = nil
            service.stop()
            renderer.detach()
            return
        }

        currentSpaceId = id
        service.start(for: id)
        renderer.attach(to: drawingAnchor)
        renderer.render(strokes: strokesAreVisible ? strokes : [])
        triggerPendingAnimationsIfNeeded()
    }
    
    func cleanup() {
        draftStroke = nil
        isOverlayVisible = false
        strokes.removeAll()
        knownStrokeIds.removeAll()
        pendingAnimations.removeAll()
        resetSelectionsToDefaults()
        activeHand = nil
        lastHandWorldPoint = nil
        service.stop()
        renderer.cancelAllAnimations()
        renderer.detach()
        drawingAnchor.removeFromParent()
        sceneRoot = nil
        handPoseProvider.stop()
    }
    
    // MARK: - Overlay Controls
    func setOverlayVisibility(_ value: Bool) {
        isOverlayVisible = value
        if value {
            handPoseProvider.start { [weak self] sample in
                self?.handleHandPoseSample(sample)
            }
            refreshFingerPreview()
            triggerPendingAnimationsIfNeeded()
        } else {
            if isHandDrawing {
                endStroke()
                isHandDrawing = false
            }
            activeHand = nil
            lastHandWorldPoint = nil
            handPoseProvider.stop()
            renderer.hideFingerPreview()
        }
    }
    
    func select(brush: SpaceDrawingBrushOption) {
        selectedBrush = brush
        selectedColor = brush.color
        selectedWidth = brush.width
        selectedMetallic = brush.metallic.clamped(to: metallicRange)
        selectedRoughness = brush.roughness.clamped(to: roughnessRange)
        selectedEmissive = brush.emissive.clamped(to: emissiveRange)
        selectedEmissiveColor = brush.emissiveColor ?? brush.color
        syncSelectedBrush()
        refreshFingerPreview()
    }
    
    func select(tool: Tool) {
        selectedTool = tool
        if tool != .brush {
            draftStroke = nil
            lastSampledPoint = nil
            if isHandDrawing {
                endStroke()
                isHandDrawing = false
            }
            activeHand = nil
        }
    }
    
    func selectWidth(_ width: Double) {
        selectedWidth = width
        syncSelectedBrush()
        refreshFingerPreview()
    }

    func updateWidth(_ value: Double) {
        selectedWidth = value.clamped(to: widthRange)
        syncSelectedBrush()
        refreshFingerPreview()
    }

    func updateMetallic(_ value: Double) {
        selectedMetallic = value.clamped(to: metallicRange)
        syncSelectedBrush()
    }

    func updateRoughness(_ value: Double) {
        selectedRoughness = value.clamped(to: roughnessRange)
        syncSelectedBrush()
    }

    func updateEmissive(_ value: Double) {
        selectedEmissive = value.clamped(to: emissiveRange)
        syncSelectedBrush()
        refreshFingerPreview()
    }

    func updateEmissiveColor(_ color: Color) {
        selectedEmissiveColor = color
        syncSelectedBrush()
        refreshFingerPreview()
    }

    func updateDepth(_ value: Double) {
        selectedDepth = value.clamped(to: depthRange)
        if isDepthLocked, drawingAnchor.parent != nil, let point = lastHandWorldPoint {
            let local = drawingAnchor.convert(position: point, from: nil)
            var adjusted = local
            adjusted.z = Float(selectedDepth)
            let lockedWorld = drawingAnchor.convert(position: adjusted, to: nil)
            lastHandWorldPoint = lockedWorld
        }
        refreshFingerPreview()
    }

    func setDepthLock(_ value: Bool) {
        guard isDepthLocked != value else { return }
        isDepthLocked = value
        if value, drawingAnchor.parent != nil, let point = lastHandWorldPoint {
            let local = drawingAnchor.convert(position: point, from: nil)
            var adjusted = local
            adjusted.z = Float(selectedDepth)
            lastHandWorldPoint = drawingAnchor.convert(position: adjusted, to: nil)
        }
        refreshFingerPreview()
    }

    func updateColor(_ color: Color) {
        let previousColor = selectedColor
        selectedColor = color
        if selectedEmissiveColor.toHex == previousColor.toHex {
            selectedEmissiveColor = color
        }
        syncSelectedBrush()
        refreshFingerPreview()
    }
    
    func undoLastStroke() {
        guard let stroke = strokes.last else { return }
        Task {
            try? await service.deleteStroke(withId: stroke.strokeId)
        }
    }
    
    func clearAll() {
        Task {
            do {
                try await service.clearAll()
            } catch {
                await MainActor.run { self.lastError = "Failed to clear drawings." }
            }
        }
    }
    
    // MARK: - Drawing Lifecycle
    func processDragChanged(at location: CGPoint, in size: CGSize) {
        switch selectedTool {
        case .brush:
            handleBrushDrag(at: location, in: size)
        case .eraser:
            handleEraserDrag(at: location, in: size)
        }
    }
    
    func processDragEnded() {
        if selectedTool == .brush {
            endStroke()
        }
    }
    
    private func handleBrushDrag(at location: CGPoint, in size: CGSize) {
        if draftStroke == nil {
            beginStroke(at: location, in: size)
        } else {
            appendPoint(at: location, in: size)
        }
    }
    
    private func handleEraserDrag(at location: CGPoint, in size: CGSize) {
        guard let point = samplePoint(at: location, in: size) else { return }
        erase(at: point)
    }
    
    private func beginStroke(at location: CGPoint, in size: CGSize) {
        guard let point = samplePoint(at: location, in: size) else { return }
        beginStroke(with: point)
    }

    private func appendPoint(at location: CGPoint, in size: CGSize) {
        guard let point = samplePoint(at: location, in: size) else { return }
        appendStrokePoint(point)
    }
    
    private func endStroke() {
        guard var draft = draftStroke,
              let spaceId = currentSpaceId,
              !draft.points.isEmpty else {
            draftStroke = nil
            lastSampledPoint = nil
            return
        }
        
        let now = Date()
        let stroke = makeStroke(from: draft, spaceId: spaceId, updatedAt: now)
        
        draftStroke = nil
        lastSampledPoint = nil
        
        strokes.append(stroke)
        knownStrokeIds.insert(stroke.strokeId)
        displayCurrentStrokes(includePreview: false)
        print("🖊️ Stroke finished with \(stroke.points.count) points at depth offset \(selectedDepth)")
        
        Task {
            do {
                try await service.submit(stroke: stroke)
            } catch {
                await MainActor.run {
                    self.lastError = "Unable to save drawing."
                    self.strokes.removeAll { $0.strokeId == stroke.strokeId }
                    self.renderer.render(strokes: self.strokes)
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func samplePoint(at location: CGPoint, in size: CGSize) -> SpaceDrawingPoint3D? {
        guard drawingAnchor.parent != nil else {
            print("⚠️ Drawing anchor not attached; skipping sample")
            return nil
        }
        let normalized = normalize(location, in: size)
        print("🖱️ Pointer normalized: \(normalized)")
        let sizeMeters = SpaceDrawingConstants.volumeSizeMeters
        let x = (normalized.x - 0.5) * Double(sizeMeters.x)
        let y = (0.5 - normalized.y) * Double(sizeMeters.y)
        let z = selectedDepth.clamped(to: depthRange)
        let localPoint = SIMD3<Float>(Float(x), Float(y), Float(z))
        let worldPoint = drawingAnchor.convert(position: localPoint, to: nil)
        print("✏️ Sampling point local=\(localPoint) world=\(worldPoint)")
        return SpaceDrawingPoint3D(position: worldPoint, timestamp: Date())
    }
    
    private func resetSelectionsToDefaults() {
        if let brush = SpaceDrawingConstants.defaultBrushes.first {
            selectedBrush = brush
            selectedColor = brush.color
            selectedWidth = brush.width
        selectedMetallic = brush.metallic
        selectedRoughness = brush.roughness
        selectedEmissive = brush.emissive
        syncSelectedBrush()
    }
    selectedTool = .brush
    selectedDepth = 0
    selectedEmissiveColor = selectedColor
        isDepthLocked = false
        refreshFingerPreview()
    }
    
    private func adoptMaterialFromLatestStrokeIfNeeded() {
        guard let latest = strokes.max(by: { $0.updatedAt < $1.updatedAt }) else { return }
        guard latest.userId != currentUserIdProvider() else { return }
        selectedMetallic = latest.metallic.clamped(to: metallicRange)
        selectedRoughness = latest.roughness.clamped(to: roughnessRange)
        selectedEmissive = latest.emission.clamped(to: emissiveRange)
        selectedColor = latest.color
        selectedEmissiveColor = latest.emissionColor
        syncSelectedBrush()
        refreshFingerPreview()
    }
    
    private func makeActiveBrush() -> SpaceDrawingBrushOption {
        SpaceDrawingBrushOption(
            id: selectedBrush.id,
            displayName: selectedBrush.displayName,
            color: selectedColor,
            width: selectedWidth,
            metallic: selectedMetallic,
            roughness: selectedRoughness,
            emissive: selectedEmissive,
            style: selectedBrush.style,
            emissiveColorHex: selectedEmissiveColor.toHex
        )
    }
    
    private func beginStroke(with point: SpaceDrawingPoint3D) {
        guard draftStroke == nil, let spaceId = currentSpaceId else { return }
        let activeBrush = makeActiveBrush()
        draftStroke = DraftStroke(
            strokeId: UUID().uuidString,
            brush: activeBrush,
            points: [point],
            metallic: activeBrush.metallic,
            roughness: activeBrush.roughness,
            emissive: activeBrush.emissive,
            createdAt: Date()
        )
        lastSampledPoint = point.simdVector
        displayCurrentStrokes(includePreview: true)
    }

    private func appendStrokePoint(_ point: SpaceDrawingPoint3D) {
        guard var draft = draftStroke else { return }
        let currentVector = point.simdVector
        if draftShouldSplit(draft: draft, nextPoint: currentVector) {
            splitActiveStroke(with: point)
            return
        }
        if let last = lastSampledPoint {
            let delta = currentVector - last
            let distanceSquared = Double(simd_length_squared(delta))
            let minimumDistanceSquared = minimumPointDistanceSquared(for: draft.brush.width)
            if distanceSquared < minimumDistanceSquared {
                return
            }
        }
        draft.points.append(point)
        draftStroke = draft
        lastSampledPoint = currentVector
        displayCurrentStrokes(includePreview: true)
    }
    
    private func draftShouldSplit(draft: DraftStroke, nextPoint: SIMD3<Float>) -> Bool {
        let brushWidth = draft.brush.width
        let normalizedWidth = normalizedBrushWidth(brushWidth)
        
        let basePointLimit = Double(SpaceDrawingConstants.maxStrokePoints)
        let pointScaleUnclamped = 0.7 + (1 - normalizedWidth) * 0.5
        let pointScale = min(max(pointScaleUnclamped, 0.7), 1.2)
        let pointLimit = max(240, Int(basePointLimit * pointScale))
        if draft.points.count >= pointLimit {
            return true
        }

        if let last = draft.points.last?.simdVector {
            let delta = nextPoint - last
            let distance = simd_length(delta)
            let maxDistance: Double = 0.28
            let minDistance: Double = 0.12
            let distanceThreshold = maxDistance - (maxDistance - minDistance) * normalizedWidth
            return distance > Float(distanceThreshold)
        }
        return false
    }

    private func normalizedBrushWidth(_ width: Double) -> Double {
        let denom = widthRange.upperBound - widthRange.lowerBound
        guard denom > 0 else { return 0 }
        return ((width - widthRange.lowerBound) / denom).clamped(to: 0...1)
    }

    private func minimumPointDistanceSquared(for width: Double) -> Double {
        let normalized = normalizedBrushWidth(width)
        let minMeters: Double = 0.003 + (0.016 - 0.003) * normalized
        return minMeters * minMeters
    }
    
    private func splitActiveStroke(with newPoint: SpaceDrawingPoint3D) {
        guard var draft = draftStroke, let spaceId = currentSpaceId else { return }
        draftStroke = nil
        lastSampledPoint = nil
        let now = Date()
        let completed = makeStroke(from: draft, spaceId: spaceId, updatedAt: now)
        strokes.append(completed)
        knownStrokeIds.insert(completed.strokeId)
        Task {
            try? await service.submit(stroke: completed)
        }
        displayCurrentStrokes(includePreview: false)
        beginStroke(with: newPoint)
    }
    
    private func refreshFingerPreview() {
        guard let point = lastHandWorldPoint else { return }
        switch selectedTool {
        case .brush:
            let activeBrush = makeActiveBrush()
            renderer.updateFingerPreview(
                color: activeBrush.color,
                emission: activeBrush.emissive,
                emissiveColor: selectedEmissiveColor,
                width: activeBrush.width,
                worldPosition: point,
                isVisible: isOverlayVisible,
                shape: .sphere
            )
        case .eraser:
            renderer.updateFingerPreview(
                color: .pink,
                emission: 0.4,
                width: selectedWidth,
                worldPosition: point,
                isVisible: isOverlayVisible,
                shape: .square
            )
        }
    }

    private func syncSelectedBrush() {
        let base = selectedBrush
        selectedBrush = SpaceDrawingBrushOption(
            id: base.id,
            displayName: base.displayName,
            color: selectedColor,
            width: selectedWidth,
            metallic: selectedMetallic,
            roughness: selectedRoughness,
            emissive: selectedEmissive,
            style: base.style,
            emissiveColorHex: selectedEmissiveColor.toHex
        )
    }

    private func handleHandPoseSample(_ sample: SpaceDrawingHandPoseProvider.Sample) {
        guard drawingAnchor.parent != nil else { return }

        let local = drawingAnchor.convert(position: sample.position, from: nil)
        let half = SpaceDrawingConstants.volumeSizeMeters / 2
        var clampedLocal = SIMD3<Float>(
            max(-half.x, min(half.x, local.x)),
            max(-half.y, min(half.y, local.y)),
            max(-half.z, min(half.z, local.z))
        )
        let measuredDepth = Double(clampedLocal.z)
        if isDepthLocked {
            clampedLocal.z = Float(selectedDepth.clamped(to: depthRange))
        }
        let worldPoint = drawingAnchor.convert(position: clampedLocal, to: nil)
        lastHandWorldPoint = worldPoint

        switch selectedTool {
        case .eraser:
            renderer.updateFingerPreview(
                color: .pink,
                emission: 0.4,
                width: selectedWidth,
                worldPosition: worldPoint,
                isVisible: isOverlayVisible,
                shape: .square
            )
            if sample.isIndexExtended {
                erase(at: SpaceDrawingPoint3D(position: worldPoint, timestamp: Date()))
            }
            if isHandDrawing {
                endStroke()
                isHandDrawing = false
                activeHand = nil
            }
        case .brush:
            let point = SpaceDrawingPoint3D(position: worldPoint, timestamp: Date())
            guard sample.isIndexExtended else {
                if isHandDrawing, activeHand == sample.hand {
                    print("🛑 Index relaxed, ending stroke")
                    endStroke()
                    isHandDrawing = false
                }
                if activeHand == sample.hand {
                    activeHand = nil
                }
                renderer.hideFingerPreview()
                return
            }

            if let currentHand = activeHand, currentHand != sample.hand, isHandDrawing {
                return
            }

            let activeBrush = makeActiveBrush()
            renderer.updateFingerPreview(
                color: activeBrush.color,
                emission: activeBrush.emissive,
                emissiveColor: selectedEmissiveColor,
                width: activeBrush.width,
                worldPosition: worldPoint,
                isVisible: isOverlayVisible,
                shape: .sphere
            )

            let wasDrawing = isHandDrawing

            if !isHandDrawing {
                activeHand = sample.hand
                print("✍️ Index extended, starting stroke")
                beginStroke(with: point)
                isHandDrawing = true
            } else {
                appendStrokePoint(point)
            }

            if !wasDrawing && !isDepthLocked {
                selectedDepth = measuredDepth.clamped(to: depthRange)
            }
        }
    }
    
    private func erase(at point: SpaceDrawingPoint3D) {
        let center = point.simdVector
        let radius = max(Float(selectedWidth) * 2.2, eraserRadius)
        
        let targets = strokes.filter { strokeIntersects($0, with: center, radius: radius) }
        guard !targets.isEmpty else { return }
        
        let targetIDs = Set(targets.map { $0.strokeId })
        strokes.removeAll { targetIDs.contains($0.strokeId) }
        displayCurrentStrokes(includePreview: false)
        
        Task {
            for id in targetIDs {
                try? await self.service.deleteStroke(withId: id)
            }
        }
    }
    
    private func strokeIntersects(_ stroke: SpaceStroke, with center: SIMD3<Float>, radius: Float) -> Bool {
        let points = stroke.points.map { $0.simdVector }
        guard !points.isEmpty else { return false }
        if points.count == 1 {
            return simd_distance(points[0], center) <= radius
        }
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let distance = distanceFrom(point: center, toSegmentStart: start, end: end)
            if distance <= radius {
                return true
            }
        }
        return false
    }
    
    private func distanceFrom(point: SIMD3<Float>, toSegmentStart a: SIMD3<Float>, end b: SIMD3<Float>) -> Float {
        let ab = b - a
        let denom = simd_dot(ab, ab)
        guard denom > .leastNonzeroMagnitude else {
            return simd_distance(point, a)
        }
        let t = simd_dot(point - a, ab) / denom
        let clamped = max(0, min(1, t))
        let closest = a + ab * clamped
        return simd_distance(point, closest)
    }

    private func displayCurrentStrokes(includePreview: Bool) {
        guard strokesAreVisible else {
            renderer.render(strokes: [])
            return
        }
        var display = strokes
        if includePreview, let draft = draftStroke, let spaceId = currentSpaceId {
            display.append(makeStroke(from: draft, spaceId: spaceId, updatedAt: Date()))
        }
        renderer.render(strokes: display)
    }

    func setDrawingVisibility(_ isVisible: Bool) {
        guard strokesAreVisible != isVisible else { return }
        strokesAreVisible = isVisible
        if isVisible {
            triggerPendingAnimationsIfNeeded(includeExistingStrokes: true)
            renderer.render(strokes: strokes)
        } else {
            renderer.cancelAllAnimations()
            renderer.render(strokes: [])
        }
    }

    func replayStrokeAnimations() {
        guard strokesAreVisible else { return }
        triggerPendingAnimationsIfNeeded(includeExistingStrokes: true)
    }

    private func triggerPendingAnimationsIfNeeded(includeExistingStrokes: Bool = false) {
        guard strokesAreVisible, drawingAnchor.parent != nil else { return }
        let currentUser = currentUserIdProvider()
        var scheduled = Set<String>()

        if includeExistingStrokes {
            for stroke in strokes where !stroke.isDeleted && !stroke.isEraser {
                renderer.animateStroke(stroke, isLocalUser: false)
                scheduled.insert(stroke.strokeId)
            }
        }

        guard !pendingAnimations.isEmpty else { return }

        pendingAnimations.removeAll { stroke in
            guard stroke.userId != currentUser else { return false }
            if scheduled.contains(stroke.strokeId) {
                return true
            }
            renderer.animateStroke(stroke, isLocalUser: false)
            scheduled.insert(stroke.strokeId)
            return true
        }
    }

    private func makeStroke(from draft: DraftStroke, spaceId: String, updatedAt: Date) -> SpaceStroke {
        let userId = {
            let id = currentUserIdProvider()
            return id.isEmpty ? UUID().uuidString : id
        }()
        let userName = {
            let name = usernameProvider()
            return name.isEmpty ? "Guest" : name
        }()
        return SpaceStroke(
            id: nil,
            strokeId: draft.strokeId,
            spaceId: spaceId,
            userId: userId,
            userName: userName,
            colorHex: draft.brush.color.toHex ?? "#FFFFFF",
            width: draft.brush.width,
            isEraser: false,
            metallic: draft.metallic,
            roughness: draft.roughness,
            createdAt: draft.createdAt,
            updatedAt: updatedAt,
            points: draft.points,
            isDeleted: false,
            emission: draft.emissive,
            style: draft.brush.style,
            emissionColorHex: selectedEmissiveColor.toHex
        )
    }

    private func normalize(_ location: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        let clampedX = max(0, min(location.x, size.width))
        let clampedY = max(0, min(location.y, size.height))
        return (Double(clampedX / size.width), Double(clampedY / size.height))
    }
    private func makeInitialAnchorTransform(relativeTo entity: Entity) -> Transform {
        let initialOrientation = ImmersiveSpaceManager.shared.initialUserOrientation
        var worldTransform = Transform()
        worldTransform.rotation = initialOrientation
        let anchorMatrix = entity.transformMatrix(relativeTo: nil)
        let localMatrix = anchorMatrix.inverse * worldTransform.matrix
        return Transform(matrix: localMatrix)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
