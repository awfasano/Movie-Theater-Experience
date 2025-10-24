//
//  TriviaEntitySystem.swift
//  Movie Theater Experience
//
//  Entity architecture and animation system for trivia events
//

import RealityKit
import SwiftUI
import simd

/// Main entity system for trivia events
/// Hierarchy: Root -> Host | Tables -> Table_1, Table_2, etc.
@MainActor
class TriviaEntitySystem {

    // MARK: - Entity References

    private var rootEntity: Entity?
    private var hostEntity: Entity?
    private var tablesGroupEntity: Entity?
    private var tableEntities: [Int: Entity] = [:]
    private var faceTimeGroupsForTables: [Int: Entity] = [:] // FaceTime participants grouped around each table
    private var tableEffectsAnchors: [Int: Entity] = [:]
    private var tableSeatOffsets: [Int: [SIMD3<Float>]] = [:]
    private var defaultSeatsPerTable: Int = 4

    // MARK: - Setup

    /// Creates the complete trivia entity hierarchy procedurally.
    /// Call this when you do not have a pre-authored scene available.
    func setupTriviaEntities(numberOfTables: Int = 6, seatsPerTable: Int = 4) -> Entity {
        resetCollections()
        defaultSeatsPerTable = seatsPerTable

        let root = Entity()
        root.name = "TriviaRoot"

        // Host area
        let host = Entity()
        host.name = "Host"
        host.position = [0, 0, -3] // Host in front
        root.addChild(host)
        self.hostEntity = host

        // Tables group
        let tablesGroup = Entity()
        tablesGroup.name = "Tables"
        root.addChild(tablesGroup)
        self.tablesGroupEntity = tablesGroup

        // Create individual tables in a circle
        createTablesInCircle(parent: tablesGroup, count: numberOfTables, radius: 5.0, seatsPerTable: seatsPerTable)

        self.rootEntity = root
        return root
    }

    func setupTriviaEntities(numberOfTables: Int = 6) -> Entity {
        setupTriviaEntities(numberOfTables: numberOfTables, seatsPerTable: defaultSeatsPerTable)
    }

    /// Configures the system to work with a pre-authored immersive scene.
    /// - Parameters:
    ///   - existingRoot: The root entity that was loaded from storage.
    ///   - expectedTableCount: Optional count used for diagnostics/warnings.
    func prepareScene(using existingRoot: Entity, expectedTableCount: Int? = nil, defaultSeatsPerTable: Int = 4) {
        resetCollections()
        self.defaultSeatsPerTable = defaultSeatsPerTable

        rootEntity = existingRoot
        hostEntity = existingRoot.findEntity(named: "Host")
            ?? existingRoot.findEntity(named: "host")
            ?? existingRoot.findEntity(named: "HOST")

        if let tablesGroup = existingRoot.findEntity(named: "tables")
            ?? existingRoot.findEntity(named: "Tables") {
            tablesGroupEntity = tablesGroup
            registerTables(in: tablesGroup)
        } else {
            registerTables(in: existingRoot)
        }

        if let expected = expectedTableCount,
           tableEntities.count != expected {
            print("⚠️ [TriviaEntity] Expected \(expected) tables but registered \(tableEntities.count)")
        }

        // Ensure every table has helper anchors/groups.
        for (tableNumber, tableEntity) in tableEntities {
            if faceTimeGroupsForTables[tableNumber] == nil {
                if let existingGroup = tableEntity.children.first(where: { $0.name.lowercased().contains("facetimegroup") }) {
                    faceTimeGroupsForTables[tableNumber] = existingGroup
                } else {
                    let group = createFaceTimeGroup(for: tableNumber, tableEntity: tableEntity)
                    tableEntity.addChild(group)
                    faceTimeGroupsForTables[tableNumber] = group
                }
            }

            if tableEffectsAnchors[tableNumber] == nil {
                let anchor = createEffectsAnchor(for: tableNumber, parent: tableEntity)
                tableEffectsAnchors[tableNumber] = anchor
            }
        }
    }

    func configure(using existingRoot: Entity, expectedTableCount: Int? = nil) {
        prepareScene(using: existingRoot, expectedTableCount: expectedTableCount)
    }

    func configure(using existingRoot: Entity, expectedTableCount: Int?, defaultSeatsPerTable: Int) {
        prepareScene(using: existingRoot, expectedTableCount: expectedTableCount, defaultSeatsPerTable: defaultSeatsPerTable)
    }

    private func resetCollections() {
        tableEntities.removeAll()
        faceTimeGroupsForTables.removeAll()
        tableEffectsAnchors.removeAll()
        tableSeatOffsets.removeAll()
        hostEntity = nil
        tablesGroupEntity = nil
        rootEntity = nil
    }

    private func createTablesInCircle(parent: Entity, count: Int, radius: Float, seatsPerTable: Int) {
        let angleStep = (2.0 * Float.pi) / Float(count)

        for i in 0..<count {
            let tableNumber = i + 1
            let angle = Float(i) * angleStep

            // Create table entity
            let table = Entity()
            table.name = "Table_\(tableNumber)"

            // Position in circle
            let x = radius * cos(angle)
            let z = radius * sin(angle)
            table.position = [x, 0, z]

            // Rotate to face center
            table.look(at: [0, 0, 0], from: table.position, relativeTo: parent)

            // Add table model placeholder (replace with your actual model)
            addTableModel(to: table, tableNumber: tableNumber)

            // Create FaceTime participant group around this table
            let faceTimeGroup = createFaceTimeGroup(for: tableNumber, tableEntity: table)
            table.addChild(faceTimeGroup)
            self.faceTimeGroupsForTables[tableNumber] = faceTimeGroup

            parent.addChild(table)
            tableEntities[tableNumber] = table
            let effectsAnchor = createEffectsAnchor(for: tableNumber, parent: table)
            tableEffectsAnchors[tableNumber] = effectsAnchor

            let seatPositions = TableLayoutCalculator.calculateSeatPositions(around: table.position, maxSeats: seatsPerTable)
            let offsets = seatPositions.map { $0 - table.position }
            tableSeatOffsets[tableNumber] = offsets
        }
    }

    private func addTableModel(to entity: Entity, tableNumber: Int) {
        // Create a simple placeholder - replace with your actual table model
        let tableMesh = MeshResource.generateBox(width: 1.5, height: 0.8, depth: 1.0)
        let tableMaterial = SimpleMaterial(color: .blue.withAlphaComponent(0.3), isMetallic: false)
        let tableModel = ModelEntity(mesh: tableMesh, materials: [tableMaterial])
        tableModel.name = "TableModel"

        // Add table number text
        // TODO: Add 3D text or billboard with table number

        entity.addChild(tableModel)
    }

    private func createFaceTimeGroup(for tableNumber: Int, tableEntity: Entity) -> Entity {
        let group = Entity()
        group.name = "FaceTimeGroup_\(tableNumber)"

        // Position slightly above and around the table
        // Participants will be arranged in a semi-circle around the table
        group.position = [0, 1.5, 0] // Above the table

        return group
    }

    private func registerTables(in parent: Entity) {
        for child in parent.children {
            if let number = extractTableNumber(from: child.name) {
                if tableEntities[number] == nil {
                    tableEntities[number] = child
                    if faceTimeGroupsForTables[number] == nil {
                        if let existingGroup = child.children.first(where: { $0.name.lowercased().contains("facetimegroup") }) {
                            faceTimeGroupsForTables[number] = existingGroup
                        } else {
                            let group = createFaceTimeGroup(for: number, tableEntity: child)
                            child.addChild(group)
                            faceTimeGroupsForTables[number] = group
                        }
                    }

                    if tableEffectsAnchors[number] == nil {
                        let anchor = createEffectsAnchor(for: number, parent: child)
                        tableEffectsAnchors[number] = anchor
                    }

                    if tableSeatOffsets[number] == nil {
                        let offsets = collectSeatOffsets(for: number, tableEntity: child)
                        if !offsets.isEmpty {
                            tableSeatOffsets[number] = offsets
                        }
                    }
                }
            }
            registerTables(in: child)
        }
    }

    private func extractTableNumber(from name: String) -> Int? {
        let lowercased = name.lowercased()
        guard lowercased.contains("table") else { return nil }

        let digits = lowercased
            .split(whereSeparator: { !$0.isNumber })
            .first(where: { !$0.isEmpty })

        if let digits, let number = Int(digits) {
            return number
        }

        if let suffix = lowercased.split(separator: "_").last,
           let number = Int(suffix) {
            return number
        }

        return nil
    }

    private func extractSeatNumber(from name: String) -> Int? {
        let lowercased = name.lowercased()
        guard lowercased.contains("seat") || lowercased.contains("chair") else { return nil }

        let digits = lowercased
            .split(whereSeparator: { !$0.isNumber })
            .first(where: { !$0.isEmpty })

        if let digits, let number = Int(digits) {
            return number
        }

        if let suffix = lowercased.split(separator: "_").last,
           let number = Int(suffix) {
            return number
        }

        return nil
    }

    private func collectSeatOffsets(for tableNumber: Int, tableEntity: Entity) -> [SIMD3<Float>] {
        var results: [(index: Int, offset: SIMD3<Float>)] = []

        func traverse(_ entity: Entity) {
            let lowerName = entity.name.lowercased()
            if lowerName.contains("seat") || lowerName.contains("chair") {
                let index = extractSeatNumber(from: entity.name) ?? results.count
                let offset = entity.position(relativeTo: tableEntity)
                results.append((index: index, offset: offset))
            }

            for child in entity.children {
                traverse(child)
            }
        }

        traverse(tableEntity)

        guard !results.isEmpty else { return [] }

        return results
            .sorted { $0.index < $1.index }
            .map { $0.offset }
    }

    private func convert(localOffset: SIMD3<Float>, for table: Entity) -> SIMD3<Float> {
        let matrix = table.transformMatrix(relativeTo: nil)
        let vector = SIMD4<Float>(localOffset.x, localOffset.y, localOffset.z, 1)
        let transformed = matrix * vector
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
    }

    // MARK: - Public helpers

    func tableWorldPositions() -> [Int: SIMD3<Float>] {
        var positions: [Int: SIMD3<Float>] = [:]
        for (number, table) in tableEntities {
            positions[number] = table.position(relativeTo: nil)
        }
        return positions
    }

    func seatWorldPosition(for tableNumber: Int, seatIndex: Int) -> SIMD3<Float>? {
        let positions = seatWorldPositions(for: tableNumber)
        guard seatIndex >= 0, seatIndex < positions.count else { return nil }
        return positions[seatIndex]
    }

    func seatWorldPositions(for tableNumber: Int) -> [SIMD3<Float>] {
        guard let table = tableEntities[tableNumber] else { return [] }
        var offsets = tableSeatOffsets[tableNumber] ?? []
        if offsets.isEmpty {
            let tablePosition = table.position(relativeTo: nil)
            let generated = TableLayoutCalculator
                .calculateSeatPositions(around: tablePosition, maxSeats: defaultSeatsPerTable)
                .map { $0 - tablePosition }
            offsets = generated
            tableSeatOffsets[tableNumber] = offsets
        }
        return offsets.map { convert(localOffset: $0, for: table) }
    }

    func getTableWorldPositions() -> [Int: SIMD3<Float>] {
        tableWorldPositions()
    }

    func getSeatWorldPositions(for tableNumber: Int) -> [SIMD3<Float>] {
        seatWorldPositions(for: tableNumber)
    }

    func getSeatWorldPosition(for tableNumber: Int, seatIndex: Int) -> SIMD3<Float>? {
        seatWorldPosition(for: tableNumber, seatIndex: seatIndex)
    }

    func tableNumbers() -> [Int] {
        Array(tableEntities.keys)
    }

    // MARK: - FaceTime Participant Management

    /// Adds a FaceTime participant entity around a specific table
    func addFaceTimeParticipant(
        to tableNumber: Int,
        participantId: String,
        participantEntity: Entity,
        position: Int
    ) {
        guard let faceTimeGroup = faceTimeGroupsForTables[tableNumber] else {
            print("❌ [TriviaEntity] No FaceTime group for table \(tableNumber)")
            return
        }

        // Arrange participants in a semi-circle around the table
        let participantCount = faceTimeGroup.children.count
        let angleRange: Float = .pi // 180 degrees
        let angleStep = angleRange / Float(max(participantCount, 1))
        let angle = -angleRange / 2 + Float(position) * angleStep
        let radius: Float = 1.2

        let x = radius * cos(angle)
        let z = radius * sin(angle)

        participantEntity.name = participantId
        participantEntity.position = [x, 0, z]

        // Rotate to face the table center
        participantEntity.look(at: [0, -1.5, 0], from: participantEntity.position, relativeTo: faceTimeGroup)

        faceTimeGroup.addChild(participantEntity)

        print("✅ [TriviaEntity] Added participant \(participantId) to table \(tableNumber)")
    }

    /// Removes a FaceTime participant from a table
    func removeFaceTimeParticipant(from tableNumber: Int, participantId: String) {
        guard let faceTimeGroup = faceTimeGroupsForTables[tableNumber] else { return }

        if let participant = faceTimeGroup.children.first(where: { $0.name == participantId }) {
            participant.removeFromParent()
            print("✅ [TriviaEntity] Removed participant \(participantId) from table \(tableNumber)")
        }
    }

    // MARK: - Get Entities

    func getTableEntity(tableNumber: Int) -> Entity? {
        return tableEntities[tableNumber]
    }

    func getHostEntity() -> Entity? {
        return hostEntity
    }

    func getAllTableEntities() -> [Int: Entity] {
        return tableEntities
    }

    // MARK: - Animation Triggers
    
    private func createEffectsAnchor(for tableNumber: Int, parent: Entity) -> Entity {
        let effectsAnchor = Entity()
        effectsAnchor.name = "Effects_\(tableNumber)"
        effectsAnchor.position = [0, 0, 0]
        parent.addChild(effectsAnchor)
        return effectsAnchor
    }

    private func ensureEffectsAnchor(for tableNumber: Int, tableEntity: Entity) -> Entity {
        if let existing = tableEffectsAnchors[tableNumber] {
            return existing
        }

        let anchor = createEffectsAnchor(for: tableNumber, parent: tableEntity)
        tableEffectsAnchors[tableNumber] = anchor
        return anchor
    }

    /// Triggers an animation on a specific table
    func triggerAnimation(on tableNumber: Int, animation: TableAnimationType) {
        guard let tableEntity = tableEntities[tableNumber] else {
            print("❌ [TriviaEntity] Table \(tableNumber) not found")
            return
        }

        let effectsAnchor = ensureEffectsAnchor(for: tableNumber, tableEntity: tableEntity)
        print("🎬 [TriviaEntity] Triggering \(animation.rawValue) on table \(tableNumber)")

        // Execute the animation
        animation.execute(on: tableEntity, effectsAnchor: effectsAnchor)
    }
}

// MARK: - Table Animation Types

enum TableAnimationType: String {
    case correctAnswer = "correct_answer"
    case wrongAnswer = "wrong_answer"
    case celebrate = "celebrate"
    case thinking = "thinking"
    case timeWarning = "time_warning"
    case bounce = "bounce"
    case shake = "shake"
    case glow = "glow"
    case pulse = "pulse"

    /// Execute the animation on the given entity
    func execute(on entity: Entity, effectsAnchor: Entity) {
        switch self {
        case .correctAnswer:
            animateCorrectAnswer(entity, effectsAnchor: effectsAnchor)
        case .wrongAnswer:
            animateWrongAnswer(entity, effectsAnchor: effectsAnchor)
        case .celebrate:
            animateCelebrate(entity, effectsAnchor: effectsAnchor)
        case .thinking:
            animateThinking(entity, effectsAnchor: effectsAnchor)
        case .timeWarning:
            animateTimeWarning(entity, effectsAnchor: effectsAnchor)
        case .bounce:
            animateBounce(entity)
        case .shake:
            animateShake(entity)
        case .glow:
            animateGlow(entity, effectsAnchor: effectsAnchor)
        case .pulse:
            animatePulse(entity, effectsAnchor: effectsAnchor)
        }
    }

    // MARK: - Animation Implementations

    private func animateCorrectAnswer(_ entity: Entity, effectsAnchor: Entity) {
        // Green flash + upward bounce
        let originalY = entity.position.y

        // Flash green
        flashColor(entity, color: .green, duration: 0.5)
        spawnHalo(on: effectsAnchor, color: .systemGreen)

        // Bounce up
        var upTransform = entity.transform
        upTransform.translation.y = originalY + 0.3
        entity.move(to: upTransform, relativeTo: entity.parent, duration: 0.2, timingFunction: .easeOut)

        // Bounce back down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            var downTransform = entity.transform
            downTransform.translation.y = originalY
            entity.move(to: downTransform, relativeTo: entity.parent, duration: 0.3, timingFunction: .easeIn)
        }
    }

    private func animateWrongAnswer(_ entity: Entity, effectsAnchor: Entity) {
        // Red flash + shake
        flashColor(entity, color: .red, duration: 0.5)
        spawnCross(on: effectsAnchor, color: .systemRed)

        // Quick shake
        let originalX = entity.position.x
        let shakeDistance: Float = 0.1

        animateShakeSequence(entity, originalX: originalX, distance: shakeDistance, count: 3, duration: 0.05)
    }

    private func animateCelebrate(_ entity: Entity, effectsAnchor: Entity) {
        // Rainbow flash + spin + scale up
        flashColor(entity, color: .yellow, duration: 0.3)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            flashColor(entity, color: .cyan, duration: 0.3)
        }

        // Spin 360 degrees
        var spinTransform = entity.transform
        spinTransform.rotation *= simd_quatf(angle: .pi * 2, axis: [0, 1, 0])
        entity.move(to: spinTransform, relativeTo: entity.parent, duration: 0.8, timingFunction: .easeInOut)

        // Scale up and back
        animateScale(entity, to: 1.2, duration: 0.4, thenBackTo: 1.0, afterDuration: 0.4)

        spawnConfetti(on: effectsAnchor)
    }

    private func animateThinking(_ entity: Entity, effectsAnchor: Entity) {
        // Gentle blue pulsing
        flashColor(entity, color: .blue, duration: 0.8, repeatCount: 3)

        // Gentle bob up and down
        let originalY = entity.position.y
        animateBobbing(entity, originalY: originalY, distance: 0.1, duration: 1.0, repeats: 2)

        spawnOrbital(on: effectsAnchor, color: .systemBlue)
    }

    private func animateTimeWarning(_ entity: Entity, effectsAnchor: Entity) {
        // Rapid orange flashing
        for i in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                flashColor(entity, color: .orange, duration: 0.2)
            }
        }

        spawnPulseRing(on: effectsAnchor, color: .systemOrange)
    }

    private func animateBounce(_ entity: Entity) {
        let originalY = entity.position.y

        // Bounce sequence: up -> down -> up -> settle
        var upTransform = entity.transform
        upTransform.translation.y = originalY + 0.4
        entity.move(to: upTransform, relativeTo: entity.parent, duration: 0.25, timingFunction: .easeOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            var downTransform = entity.transform
            downTransform.translation.y = originalY
            entity.move(to: downTransform, relativeTo: entity.parent, duration: 0.25, timingFunction: .easeIn)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                var upTransform2 = entity.transform
                upTransform2.translation.y = originalY + 0.2
                entity.move(to: upTransform2, relativeTo: entity.parent, duration: 0.15, timingFunction: .easeOut)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    var settleTransform = entity.transform
                    settleTransform.translation.y = originalY
                    entity.move(to: settleTransform, relativeTo: entity.parent, duration: 0.15, timingFunction: .easeIn)
                }
            }
        }
    }

    private func animateShake(_ entity: Entity) {
        let originalX = entity.position.x
        animateShakeSequence(entity, originalX: originalX, distance: 0.15, count: 5, duration: 0.08)
    }

    private func animateGlow(_ entity: Entity, effectsAnchor: Entity) {
        // Cyan glow pulse
        flashColor(entity, color: .cyan, duration: 0.5)
        animateScale(entity, to: 1.1, duration: 0.5, thenBackTo: 1.0, afterDuration: 0.5)

        spawnGlowSphere(on: effectsAnchor, color: .systemTeal)
    }

    private func animatePulse(_ entity: Entity, effectsAnchor: Entity) {
        // Rapid scale pulsing
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                animateScale(entity, to: 1.15, duration: 0.2, thenBackTo: 1.0, afterDuration: 0.2)
            }
        }

        spawnVerticalPulse(on: effectsAnchor, color: .systemPurple)
    }

    // MARK: - Animation Helpers (Reusable)

    private func flashColor(_ entity: Entity, color: UIColor, duration: Double, repeatCount: Int = 0) {
        guard let modelEntity = entity.findEntity(named: "TableModel") as? ModelEntity else { return }

        let flashMaterial = SimpleMaterial(color: color.withAlphaComponent(0.5), isMetallic: false)
        let originalMaterials = modelEntity.model?.materials ?? []

        modelEntity.model?.materials = [flashMaterial]

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            modelEntity.model?.materials = originalMaterials
        }

        if repeatCount > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 1.2) {
                self.flashColor(entity, color: color, duration: duration, repeatCount: repeatCount - 1)
            }
        }
    }

    private func animateScale(_ entity: Entity, to scale: Float, duration: Double, thenBackTo originalScale: Float, afterDuration: Double) {
        var scaleUpTransform = entity.transform
        scaleUpTransform.scale = [scale, scale, scale]
        entity.move(to: scaleUpTransform, relativeTo: entity.parent, duration: duration, timingFunction: .easeOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + afterDuration) {
            var scaleDownTransform = entity.transform
            scaleDownTransform.scale = [originalScale, originalScale, originalScale]
            entity.move(to: scaleDownTransform, relativeTo: entity.parent, duration: duration, timingFunction: .easeIn)
        }
    }

    private func animateShakeSequence(_ entity: Entity, originalX: Float, distance: Float, count: Int, duration: Double) {
        for i in 0..<count {
            let offset = (i % 2 == 0) ? distance : -distance

            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * duration) {
                var shakeTransform = entity.transform
                shakeTransform.translation.x = originalX + offset
                entity.move(to: shakeTransform, relativeTo: entity.parent, duration: duration, timingFunction: .linear)
            }
        }

        // Return to original position
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(count) * duration) {
            var resetTransform = entity.transform
            resetTransform.translation.x = originalX
            entity.move(to: resetTransform, relativeTo: entity.parent, duration: duration, timingFunction: .linear)
        }
    }

    private func animateBobbing(_ entity: Entity, originalY: Float, distance: Float, duration: Double, repeats: Int) {
        guard repeats > 0 else { return }

        var upTransform = entity.transform
        upTransform.translation.y = originalY + distance
        entity.move(to: upTransform, relativeTo: entity.parent, duration: duration / 2, timingFunction: .easeInOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration / 2) {
            var downTransform = entity.transform
            downTransform.translation.y = originalY
            entity.move(to: downTransform, relativeTo: entity.parent, duration: duration / 2, timingFunction: .easeInOut)

            DispatchQueue.main.asyncAfter(deadline: .now() + duration / 2) {
                self.animateBobbing(entity, originalY: originalY, distance: distance, duration: duration, repeats: repeats - 1)
            }
        }
    }

    private func spawnHalo(on anchor: Entity, color: UIColor, baseScale: Float = 0.4, duration: Double = 0.8) {
        let ringMesh = MeshResource.generateCylinder(height: 0.02, radius: 0.9)
        var material = SimpleMaterial()
        material.baseColor = .color(color.withAlphaComponent(0.35))
        material.metallic = .float(0.05)
        material.roughness = .float(0.2)

        let halo = ModelEntity(mesh: ringMesh, materials: [material])
        halo.name = "HaloEffect"
        halo.position = [0, 0.25, 0]
        halo.scale = [baseScale, baseScale, baseScale]
        anchor.addChild(halo)

        var targetTransform = halo.transform
        targetTransform.scale = [baseScale * 2.0, baseScale * 2.0, baseScale * 2.0]
        halo.move(to: targetTransform, relativeTo: halo.parent, duration: duration, timingFunction: AnimationTimingFunction.easeOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.6) {
            halo.components[OpacityComponent.self] = OpacityComponent(opacity: 0.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
            halo.removeFromParent()
        }
    }

    private func spawnConfetti(on anchor: Entity) {
        let colors: [UIColor] = [
            .systemPink, .systemBlue, .systemYellow, .systemGreen, .systemPurple, .systemOrange
        ]

        for _ in 0..<24 {
            let confetti = ModelEntity(mesh: MeshResource.generateBox(size: 0.05))
            confetti.name = "ConfettiPiece"
            confetti.model?.materials = [SimpleMaterial(color: colors.randomElement()!, isMetallic: false)]
            confetti.position = [
                Float.random(in: -0.5...0.5),
                1.2,
                Float.random(in: -0.5...0.5)
            ]
            anchor.addChild(confetti)

            var endTransform = confetti.transform
            endTransform.translation.y = Float.random(in: 0.0...0.2)
            endTransform.translation.x += Float.random(in: -0.2...0.2)
            endTransform.translation.z += Float.random(in: -0.2...0.2)
            endTransform.rotation *= simd_quatf(angle: Float.random(in: -.pi...(.pi)), axis: [0, 1, 0])

            let duration = Double.random(in: 1.0...1.4)
            confetti.move(to: endTransform, relativeTo: confetti.parent, duration: duration, timingFunction: .easeIn)

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                confetti.components[OpacityComponent.self] = OpacityComponent(opacity: 0.0)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3) {
                confetti.removeFromParent()
            }
        }
    }

    private func spawnOrbital(on anchor: Entity, color: UIColor) {
        let orbitRoot = Entity()
        orbitRoot.name = "ThinkingOrbit"
        orbitRoot.position = [0, 0.35, 0]

        let orb = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.06))
        orb.model?.materials = [SimpleMaterial(color: color.withAlphaComponent(0.8), isMetallic: false)]
        orb.position = [0.45, 0, 0]
        orbitRoot.addChild(orb)

        anchor.addChild(orbitRoot)

        var rotation = orbitRoot.transform
        rotation.rotation *= simd_quatf(angle: .pi * 2, axis: [0, 1, 0])
        orbitRoot.move(to: rotation, relativeTo: orbitRoot.parent, duration: 3.0, timingFunction: .linear)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            orbitRoot.removeFromParent()
        }
    }

    private func spawnPulseRing(on anchor: Entity, color: UIColor) {
        let ringMesh = MeshResource.generateCylinder(height: 0.015, radius: 0.9)
        let material = SimpleMaterial(color: color.withAlphaComponent(0.6), isMetallic: false)

        let ring = ModelEntity(mesh: ringMesh, materials: [material])
        ring.name = "WarningRing"
        ring.position = [0, 0.3, 0]
        ring.scale = [0.3, 0.3, 0.3]
        anchor.addChild(ring)

        var target = ring.transform
        target.scale = [1.6, 1.6, 1.6]
        ring.move(to: target, relativeTo: ring.parent, duration: 0.8, timingFunction: AnimationTimingFunction.easeOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            ring.components[OpacityComponent.self] = OpacityComponent(opacity: 0.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ring.removeFromParent()
        }
    }

    private func spawnGlowSphere(on anchor: Entity, color: UIColor) {
        let sphere = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.12))
        sphere.name = "GlowSphere"
        sphere.position = [0, 0.4, 0]
        sphere.model?.materials = [SimpleMaterial(color: color.withAlphaComponent(0.5), isMetallic: true)]
        anchor.addChild(sphere)

        var target = sphere.transform
        target.scale = [1.8, 1.8, 1.8]
        sphere.move(to: target, relativeTo: sphere.parent, duration: 0.6, timingFunction: AnimationTimingFunction.easeInOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            sphere.components[OpacityComponent.self] = OpacityComponent(opacity: 0.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            sphere.removeFromParent()
        }
    }

    private func spawnVerticalPulse(on anchor: Entity, color: UIColor) {
        let beam = ModelEntity(mesh: MeshResource.generateBox(size: [0.12, 1.1, 0.12]))
        beam.name = "PulseBeam"
        beam.model?.materials = [SimpleMaterial(color: color.withAlphaComponent(0.35), isMetallic: false)]
        beam.position = [0, 0.6, 0]
        anchor.addChild(beam)

        var target = beam.transform
        target.translation.y = 0.2
        beam.move(to: target, relativeTo: beam.parent, duration: 0.35, timingFunction: AnimationTimingFunction.easeOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            beam.components[OpacityComponent.self] = OpacityComponent(opacity: 0.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            beam.removeFromParent()
        }
    }

    private func spawnCross(on anchor: Entity, color: UIColor) {
        let crossRoot = Entity()
        crossRoot.name = "WrongCross"
        crossRoot.position = [0, 0.35, 0]

        let barMesh = MeshResource.generateBox(size: [0.7, 0.08, 0.02])
        let material = SimpleMaterial(color: color.withAlphaComponent(0.8), isMetallic: false)

        let bar1 = ModelEntity(mesh: barMesh, materials: [material])
        bar1.orientation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1])

        let bar2 = ModelEntity(mesh: barMesh, materials: [material])
        bar2.orientation = simd_quatf(angle: -.pi / 4, axis: [0, 0, 1])

        crossRoot.addChild(bar1)
        crossRoot.addChild(bar2)

        anchor.addChild(crossRoot)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            crossRoot.components[OpacityComponent.self] = OpacityComponent(opacity: 0.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            crossRoot.removeFromParent()
        }
    }
}
