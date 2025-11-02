import XCTest
@testable import Movie_Theater_Experience

final class FlowLayoutEngineTests: XCTestCase {
    
    func testLayoutKeepsItemsOnSingleLineWhenSpaceAllows() {
        let sizes = [
            CGSize(width: 50, height: 20),
            CGSize(width: 60, height: 25),
            CGSize(width: 40, height: 15)
        ]
        let engine = FlowLayoutEngine(spacing: 10)
        let result = engine.layout(sizes: sizes, maxWidth: 500)
        
        XCTAssertEqual(result.positions.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(result.positions[1], CGPoint(x: 60, y: 0))
        XCTAssertEqual(result.positions[2], CGPoint(x: 130, y: 0))
        XCTAssertEqual(result.totalHeight, 25)
    }
    
    func testLayoutWrapsToNextLineWhenExceeded() {
        let sizes = [
            CGSize(width: 80, height: 20),
            CGSize(width: 80, height: 30),
            CGSize(width: 90, height: 15)
        ]
        let engine = FlowLayoutEngine(spacing: 10)
        let result = engine.layout(sizes: sizes, maxWidth: 180)
        
        XCTAssertEqual(result.positions[0], CGPoint(x: 0, y: 0))
        XCTAssertEqual(result.positions[1], CGPoint(x: 90, y: 0))
        XCTAssertEqual(result.positions[2], CGPoint(x: 0, y: 40)) // second row
        XCTAssertEqual(result.totalHeight, 55)
    }
    
    func testLayoutReturnsZeroHeightForEmptyInput() {
        let engine = FlowLayoutEngine(spacing: 10)
        let result = engine.layout(sizes: [], maxWidth: 100)
        XCTAssertEqual(result.positions.count, 0)
        XCTAssertEqual(result.totalHeight, 0)
    }
}
