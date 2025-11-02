import XCTest
import RealityKit
@testable import Movie_Theater_Experience

final class SpaceImmersionSpaceDataTests: XCTestCase {
    func testOccupancyPercentageCalculations() {
        var data = makeSpace(current: 50, max: 100)
        XCTAssertEqual(data.occupancyPercentage, 0.5)
        data.maxUserCount = 0
        XCTAssertEqual(data.occupancyPercentage, 0)
    }
    
    func testViewerAdjustment() {
        let data = makeSpace(x: 1.5, y: -0.5, z: 2.25)
        let adjustment = data.viewerAdjustment
        XCTAssertEqual(adjustment.x, 1.5, accuracy: 0.001)
        XCTAssertEqual(adjustment.y, -0.5, accuracy: 0.001)
        XCTAssertEqual(adjustment.z, 2.25, accuracy: 0.001)
    }
    
    private func makeSpace(current: Int = 0, max: Int = 100, x: Double = 0, y: Double = 0, z: Double = 0) -> SpaceData {
        SpaceData(
            id: "space",
            spaceName: "Test",
            description: "",
            lastModified: Date(),
            usdzURL: "https://example.com/space.usdz",
            thumbnailURL: nil,
            mapURL: nil,
            attributions: nil,
            tags: nil,
            introEntityName: nil,
            currentSeat: nil,
            ambient_audio: nil,
            initialTargetEntityForVolume: nil,
            viewerXAdjustment: x,
            viewerYAdjustment: y,
            viewerZAdjustment: z,
            volumeInitialScale: nil,
            volumeOffsetX: nil,
            volumeOffsetY: nil,
            volumeOffsetZ: nil,
            currentUserCount: current,
            maxUserCount: max,
            mapImageURL: nil,
            seats: nil
        )
    }
}
