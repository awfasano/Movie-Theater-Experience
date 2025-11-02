import XCTest
@testable import Movie_Theater_Experience

final class SpaceDetailViewModelTests: XCTestCase {
    
    func testFormattedDateUsesLongStyle() {
        var components = DateComponents()
        components.year = 2025
        components.month = 10
        components.day = 24
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: components)!
        
        let space = makeSpace(lastModified: date)
        let viewModel = SpaceDetailViewModel(space: space)
        
        XCTAssertEqual(viewModel.formattedLastModified, "October 24, 2025")
    }
    
    func testTagsPresenceFlagsCorrectly() {
        let spaceWithTags = makeSpace(tags: ["Lounge", "Music"])
        let vmWithTags = SpaceDetailViewModel(space: spaceWithTags)
        XCTAssertTrue(vmWithTags.hasTags)
        XCTAssertEqual(vmWithTags.tags, ["Lounge", "Music"])
        
        let spaceWithoutTags = makeSpace(tags: nil)
        let vmWithoutTags = SpaceDetailViewModel(space: spaceWithoutTags)
        XCTAssertFalse(vmWithoutTags.hasTags)
    }
    
    func testOriginalURL() {
        let space = makeSpace(usdzURL: "https://example.com/scene.usdz")
        let viewModel = SpaceDetailViewModel(space: space)
        XCTAssertEqual(viewModel.originalSceneURL, URL(string: "https://example.com/scene.usdz"))
        
        let invalid = makeSpace(usdzURL: "not a url")
        XCTAssertEqual(SpaceDetailViewModel(space: invalid).originalSceneURL?.absoluteString, "not%20a%20url")
    }
    
    // MARK: - Helpers
    private func makeSpace(
        usdzURL: String = "https://example.com/scene.usdz",
        lastModified: Date = Date(),
        tags: [String]? = ["Tag"]
    ) -> SpaceData {
        SpaceData(
            id: UUID().uuidString,
            spaceName: "Demo Space",
            description: "Description",
            lastModified: lastModified,
            usdzURL: usdzURL,
            thumbnailURL: nil,
            mapURL: nil,
            attributions: nil,
            tags: tags,
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
