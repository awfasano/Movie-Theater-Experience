import XCTest
@testable import Movie_Theater_Experience

final class WatchStatsTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let stats = WatchStats(watchTime: 120, viewerCount: 42)
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(WatchStats.self, from: data)
        XCTAssertEqual(decoded, stats)
    }
    
    func testHashableBehavior() {
        let statsA = WatchStats(watchTime: 10, viewerCount: 1)
        let statsB = WatchStats(watchTime: 10, viewerCount: 1)
        let statsC = WatchStats(watchTime: 20, viewerCount: 2)
        
        let set: Set = [statsA, statsB, statsC]
        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(statsC))
    }
}
