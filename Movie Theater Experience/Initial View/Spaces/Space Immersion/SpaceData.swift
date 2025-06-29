import Foundation
import FirebaseFirestore
import RealityKit

struct SpaceData: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var spaceName: String
    var description: String
    var lastModified: Date
    var usdzURL: String
    var thumbnailURL: String?
    var mapURL: String?
    var attributions: String?
    var tags: [String]?
    var introEntityName: String?
    var currentSeat:String?
    
    // ✅ RENAMED: Property is now more specific.
    var initialTargetEntityForVolume: String?
    
    // Viewer position adjustments
    var viewerXAdjustment: Double = 0.0
    var viewerYAdjustment: Double = 0.0
    var viewerZAdjustment: Double = 0.0
    
    var volumeInitialScale: Double?
    var volumeOffsetX: Double?
    var volumeOffsetY: Double?
    var volumeOffsetZ: Double?
    
    
    // User count tracking
    var currentUserCount: Int = 0
    var maxUserCount: Int = 1000  // Default max capacity
    
    // Seat mapping properties
    var mapImageURL: String?
    var seats: [SeatPosition]?
    
    // Computed property for occupancy percentage
    var occupancyPercentage: Float {
        guard maxUserCount > 0 else { return 0 }
        return Float(currentUserCount) / Float(maxUserCount)
    }
    
    // Computed property for viewer adjustment as SIMD3
    var viewerAdjustment: SIMD3<Float> {
        return SIMD3<Float>(Float(viewerXAdjustment), Float(viewerYAdjustment), Float(viewerZAdjustment))
    }
}
