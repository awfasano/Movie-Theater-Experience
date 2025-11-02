import XCTest
import SwiftUI
@testable import Movie_Theater_Experience

final class SpaceCardViewModelTests: XCTestCase {
    
    func testOccupancyColorMapping() {
        let baseSpace = SpaceData(
            id: "space",
            spaceName: "Test Space",
            description: "Desc",
            lastModified: Date(),
            usdzURL: "https://example.com/model.usdz",
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
            currentUserCount: 10,
            maxUserCount: 100,
            mapImageURL: nil,
            seats: nil
        )
        
        let lowOccupancy = SpaceCardViewModel(space: baseSpace)
        XCTAssertEqual(lowOccupancy.occupancy.color, .green)
        
        var mediumSpace = baseSpace
        mediumSpace.currentUserCount = 70
        let mediumOccupancy = SpaceCardViewModel(space: mediumSpace)
        XCTAssertEqual(mediumOccupancy.occupancy.color, .yellow)
        
        var highSpace = baseSpace
        highSpace.currentUserCount = 90
        let highOccupancy = SpaceCardViewModel(space: highSpace)
        XCTAssertEqual(highOccupancy.occupancy.color, .red)
    }
    
    func testDisplayTextUsesUserCount() {
        var space = makeSpace(userCount: 42)
        let viewModel = SpaceCardViewModel(space: space)
        XCTAssertEqual(viewModel.occupancy.displayText, "42 users")
        
        space.currentUserCount = 1
        let singleUserVM = SpaceCardViewModel(space: space)
        XCTAssertEqual(singleUserVM.occupancy.displayText, "1 users")
    }
    
    func testThumbnailURLReflectsOptionalValue() {
        let space = makeSpace(userCount: 10, thumbnail: "https://example.com/image.jpg")
        let vm = SpaceCardViewModel(space: space)
        XCTAssertEqual(vm.thumbnailURL, URL(string: "https://example.com/image.jpg"))
        
        let noThumb = SpaceCardViewModel(space: makeSpace(userCount: 10))
        XCTAssertNil(noThumb.thumbnailURL)
    }
    
    // MARK: - Helpers
    private func makeSpace(userCount: Int, thumbnail: String? = nil) -> SpaceData {
        SpaceData(
            id: UUID().uuidString,
            spaceName: "Space",
            description: "",
            lastModified: Date(),
            usdzURL: "https://example.com/model.usdz",
            thumbnailURL: thumbnail,
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
            currentUserCount: userCount,
            maxUserCount: 100,
            mapImageURL: nil,
            seats: nil
        )
    }
}
