
import XCTest
import RealityKit
@testable import Movie_Theater_Experience

class SpaceDataTests: XCTestCase {

    func testInitialization() {
        let date = Date()
        let space = SpaceData(id: "1", spaceName: "Test Space", description: "A test space", lastModified: date, usdzURL: "url", thumbnailURL: "thumb", mapURL: "map", attributions: "attrib", tags: ["tag1"], introEntityName: "intro", currentSeat: "A1", viewerXAdjustment: 1, viewerYAdjustment: 2, viewerZAdjustment: 3, currentUserCount: 10, maxUserCount: 20, mapImageURL: "map_image", seats: [])
        XCTAssertEqual(space.id, "1")
        XCTAssertEqual(space.spaceName, "Test Space")
        // ... and so on for all properties
    }
    func testOccupancyPercentage() {
        var space = SpaceData(spaceName: "", description: "", lastModified: Date(), usdzURL: "")
        space.currentUserCount = 5
        space.maxUserCount = 10
        XCTAssertEqual(space.occupancyPercentage, 0.5, accuracy: 0.01)
        
        space.maxUserCount = 0
        XCTAssertEqual(space.occupancyPercentage, 0.0, accuracy: 0.01)
    }

    func testViewerAdjustment() {
        var space = SpaceData(spaceName: "", description: "", lastModified: Date(), usdzURL: "")
        space.viewerXAdjustment = 1.0
        space.viewerYAdjustment = 2.0
        space.viewerZAdjustment = 3.0
        
        let expectedAdjustment = SIMD3<Float>(1.0, 2.0, 3.0)
        XCTAssertEqual(space.viewerAdjustment, expectedAdjustment)
    }
}
