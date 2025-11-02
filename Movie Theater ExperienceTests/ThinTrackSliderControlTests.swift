import XCTest
@testable import Movie_Theater_Experience

final class ThinTrackSliderControlTests: XCTestCase {
    func testTrackRectCentersThinRail() {
        let slider = ThinTrackSliderControl(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        let rect = slider.trackRect(forBounds: slider.bounds)
        
        XCTAssertEqual(rect.height, 3, accuracy: 0.001)
        XCTAssertEqual(rect.width, 200, accuracy: 0.001)
        XCTAssertEqual(rect.minY, (40 - 3) / 2, accuracy: 0.001)
    }
}
