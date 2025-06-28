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
}