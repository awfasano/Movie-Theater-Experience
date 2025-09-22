import Foundation
import simd

public final class PersonaTableManager: ObservableObject {
    // Positions for tables keyed by table number
    private var tablePositions: [Int: SIMD3<Float>] = [:]
    // Current user's position
    private var currentUserPosition: SIMD3<Float>? = nil

    public init() {}

    // MARK: - API expected by ParticipantSpatialUI

    public func getTablePosition(_ tableNumber: Int) -> SIMD3<Float>? {
        tablePositions[tableNumber]
    }

    public func getCurrentUserPosition() -> SIMD3<Float>? {
        currentUserPosition
    }

    // MARK: - Helpers to set positions (optional for the rest of the app to use)

    public func setTablePosition(_ position: SIMD3<Float>, for tableNumber: Int) {
        tablePositions[tableNumber] = position
    }

    public func setCurrentUserPosition(_ position: SIMD3<Float>?) {
        currentUserPosition = position
    }
}
