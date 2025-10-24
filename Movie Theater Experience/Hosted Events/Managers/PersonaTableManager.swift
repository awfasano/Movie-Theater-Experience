import Foundation
import simd

@MainActor
final class PersonaTableManager: ObservableObject {
    // Positions for tables keyed by table number
    private var tablePositions: [Int: SIMD3<Float>] = [:]
    private var tableSeatPositions: [Int: [SIMD3<Float>]] = [:]
    // Current user's position
    private var currentUserPosition: SIMD3<Float>? = nil

    init() {}

    // MARK: - API expected by ParticipantSpatialUI

    func getTablePosition(_ tableNumber: Int) -> SIMD3<Float>? {
        tablePositions[tableNumber]
    }

    func getCurrentUserPosition() -> SIMD3<Float>? {
        currentUserPosition
    }

    // MARK: - Helpers to set positions (optional for the rest of the app to use)

    func setTablePosition(_ position: SIMD3<Float>, for tableNumber: Int) {
        tablePositions[tableNumber] = position
    }

    func setSeatPositions(_ positions: [SIMD3<Float>], for tableNumber: Int) {
        tableSeatPositions[tableNumber] = positions
    }

    func seatPosition(for tableNumber: Int, seatIndex: Int) -> SIMD3<Float>? {
        guard let seats = tableSeatPositions[tableNumber], seatIndex >= 0, seatIndex < seats.count else {
            return nil
        }
        return seats[seatIndex]
    }

    func setCurrentUserPosition(_ position: SIMD3<Float>?) {
        currentUserPosition = position
    }
}

extension PersonaTableManager: PersonaTableUpdatable {
    func updatePersonaForUser(_ participant: EventParticipant, tables: [EventTable]) async {
        guard let tableNumber = participant.tableNumber,
              let seatIndex = participant.seatIndex,
              let seat = seatPosition(for: tableNumber, seatIndex: seatIndex) else {
            if let fallback = tablePositions[participant.tableNumber ?? -1] {
                await MainActor.run {
                    setCurrentUserPosition(fallback)
                }
            }
            return
        }

        await MainActor.run {
            setCurrentUserPosition(seat)
        }
    }
}
