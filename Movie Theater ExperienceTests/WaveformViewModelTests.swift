import XCTest
@testable import Movie_Theater_Experience

@MainActor
final class WaveformViewModelTests: XCTestCase {
    func testApplyUsesSmoothingAndMaintainsWindow() {
        let viewModel = WaveformViewModel()
        viewModel.audioLevels = Array(repeating: 0.5, count: 50)
        
        viewModel.apply(level: 1.0)
        
        XCTAssertEqual(viewModel.audioLevels.count, 50)
        XCTAssertEqual(viewModel.audioLevels.last ?? 0, 0.5 * 0.6 + 1.0 * 0.4, accuracy: 0.0001)
    }
    
    func testApplyShiftsOldestSample() {
        let viewModel = WaveformViewModel()
        viewModel.audioLevels = Array(0..<50).map { Float($0) }
        let firstBefore = viewModel.audioLevels.first
        
        viewModel.apply(level: 0)
        
        XCTAssertNotEqual(viewModel.audioLevels.first, firstBefore)
        XCTAssertEqual(viewModel.audioLevels.count, 50)
    }
}
