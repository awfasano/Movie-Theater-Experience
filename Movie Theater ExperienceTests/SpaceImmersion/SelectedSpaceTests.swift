import XCTest
@testable import Movie_Theater_Experience

final class SelectedSpaceTests: XCTestCase {
    func testSelectedSpaceDefaultsToNil() {
        let selected = SelectedSpace()
        XCTAssertNil(selected.space)
        XCTAssertNil(selected.currentSeat)
    }
    
    func testSelectedSpaceStoresValues() {
        let selected = SelectedSpace()
        let space = SpaceData(
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
        selected.space = space
        selected.currentSeat = "seat_1"
        XCTAssertEqual(selected.space?.spaceName, "Test")
        XCTAssertEqual(selected.currentSeat, "seat_1")
    }
}
