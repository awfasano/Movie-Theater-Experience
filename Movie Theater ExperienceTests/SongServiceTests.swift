
import XCTest
@testable import Movie_Theater_Experience

class SongServiceTests: XCTestCase {

    var songService: SongService!

    override func setUp() {
        super.setUp()
        songService = SongService()
    }

    override func tearDown() {
        songService = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(songService)
    }

    func testFetchSongs() {
        // This is difficult to test without a mock Firestore.
        // We would need to inject a mock Firestore instance into SongService
        // to properly test this functionality.
    }
}
