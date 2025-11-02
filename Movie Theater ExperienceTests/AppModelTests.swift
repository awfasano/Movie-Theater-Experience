import XCTest
@testable import Movie_Theater_Experience

@MainActor
class AppModelTests: XCTestCase {

    var appModel: AppModel!

    override func setUp() {
        super.setUp()
        appModel = AppModel()
    }

    override func tearDown() {
        appModel = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(appModel)
        XCTAssertNil(appModel.selectedSpace)
    }

    func testSelectSpace() {
        let space = SpaceData(spaceName: "Test Space", description: "A test space", lastModified: Date(), usdzURL: "url")
        appModel.selectedSpace = space
        XCTAssertEqual(appModel.selectedSpace, space)
    }
    
    func testUpdateSelectedSpaceSeatUpdatesCurrentSeat() {
        let space = SpaceData(
            id: "space1",
            spaceName: "Test",
            description: "Desc",
            lastModified: Date(),
            usdzURL: "https://example.com/space.usdz",
            thumbnailURL: nil,
            mapURL: nil,
            attributions: nil,
            tags: nil,
            introEntityName: nil,
            currentSeat: "seat_1",
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
        
        appModel.selectedSpace = space
        appModel.updateSelectedSpaceSeat(to: "seat_2")
        
        XCTAssertEqual(appModel.selectedSpace?.currentSeat, "seat_2")
    }
}
