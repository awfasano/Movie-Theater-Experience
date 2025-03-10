import SwiftUI
import RealityKit

struct TheaterRow: Identifiable {
    let id: String
    let entity: Entity
    let rowNumber: Int
    var seats: [TheaterSeat]
}

struct TheaterSeat: Identifiable {
    let id: String
    let entity: Entity
    let seatNumber: Int
}

class SharedSeatSelection: ObservableObject {
    static let shared = SharedSeatSelection()
    @Published var selectedSeatEntity: Entity?
    @Published var currentRow: Int?
    @Published var currentSeat: Int?
}
