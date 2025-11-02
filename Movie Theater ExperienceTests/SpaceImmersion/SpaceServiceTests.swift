import XCTest
@testable import Movie_Theater_Experience

final class SpaceServiceTests: XCTestCase {
    func testMakeSpaceHelperProducesValidSpace() {
        let space = makeSpace(id: "space-1", name: "Lounge")
        XCTAssertEqual(space.id, "space-1")
        XCTAssertEqual(space.spaceName, "Lounge")
    }

    private func makeSpace(id: String, name: String) -> SpaceData {
        SpaceData(
            id: id,
            spaceName: name,
            description: "",
            lastModified: Date(),
            usdzURL: "https://example.com/\(id).usdz",
            thumbnailURL: nil,
            mapURL: nil,
            attributions: nil,
            tags: nil,
            introEntityName: nil,
            currentSeat: nil,
            ambient_audio: nil,
            initialTargetEntityForVolume: nil,
            viewerXAdjustment: 0,
            viewerYAdjustment: 0,
            viewerZAdjustment: 0,
            volumeInitialScale: nil,
            volumeOffsetX: nil,
            volumeOffsetY: nil,
            volumeOffsetZ: nil,
            currentUserCount: 0,
            maxUserCount: 100,
            mapImageURL: nil,
            seats: nil
        )
    }
}
