import Foundation
import GroupActivities
import SwiftUI
import simd

@available(visionOS 1.0, *)
@MainActor
class PersonaTableManager: ObservableObject {
    static let shared = PersonaTableManager()
    
    @Published private(set) var groupSession: GroupSession<TriviaEventActivity>?
    @Published private(set) var participants: [EventParticipant] = []
    @Published private(set) var personaPositions: [String: PersonaTablePosition] = [:]
    @Published private(set) var isConnected = false
    
    private var messenger: GroupSessionMessenger?
    private var tableLayouts: [Int: SIMD3<Float>] = [:]
    
    func startTriviaActivity(eventId: String, eventTitle: String, spaceId: String) async throws { }
    func assignPersonaToTable(userId: String, tableNumber: Int) async { }
    func movePersonaToHostPosition(userId: String) async { }
    
    // --- New: Update persona position and broadcast ---
    func updatePersonaForUser(_ user: EventParticipant, tables: [EventTable]) async {
        guard let tableNum = user.tableNumber,
              let seatIdx = user.seatIndex,
              let table = tables.first(where: { $0.tableNumber == tableNum }),
              table.seatPositions.indices.contains(seatIdx)
        else { return }
        let position = table.seatPositions[seatIdx]
        let rotation = TableLayoutCalculator.calculateSeatRotation(tablePosition: table.tablePosition, seatPosition: position)
        let personaPosition = PersonaTablePosition(userId: user.userId, userName: user.userName, tableNumber: tableNum, seatIndex: seatIdx, position: position, rotation: rotation)
        personaPositions[user.userId] = personaPosition
        await broadcastPersonaPosition(personaPosition)
    }

    func broadcastPersonaPosition(_ position: PersonaTablePosition) async {
        guard let messenger = messenger else { return }
        do {
            try await messenger.send(PersonaMessage.positionUpdate(position))
        } catch {
            print("Error broadcasting persona position: \(error)")
        }
    }
    
    func calculateOptimalTableLayout(for configuration: TableConfiguration) -> [Int: SIMD3<Float>] {
        return TableLayoutCalculator.calculateTablePositions(for: configuration.layoutType, maxTables: configuration.maxTables)
    }
}
