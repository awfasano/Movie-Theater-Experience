import SwiftUI
import RealityKit

class SharedSeatSelection: ObservableObject {
    static let shared = SharedSeatSelection()
    @Published var selectedSeatEntity: Entity?
}
