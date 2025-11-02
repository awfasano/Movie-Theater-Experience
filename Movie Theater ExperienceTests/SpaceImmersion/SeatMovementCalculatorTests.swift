import XCTest
import simd
@testable import Movie_Theater_Experience

final class SeatMovementCalculatorTests: XCTestCase {
    
    func testCalculateReturnsAdjustedAnchorPosition() {
        let input = SeatMovementInput(
            seatLocalPosition: SIMD3<Float>(1, 0, 0),
            viewerAdjustment: SIMD3<Float>(0, 0, 0),
            verticalOffset: 0,
            userRotationDegrees: 0,
            seatRotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        )
        
        let result = SeatMovementCalculator.calculate(input: input)
        XCTAssertEqual(result.anchorPosition.x, -1, accuracy: 0.0001)
        XCTAssertEqual(result.anchorPosition.y, 0, accuracy: 0.0001)
        XCTAssertEqual(result.anchorPosition.z, 0, accuracy: 0.0001)
    }
    
    func testCalculateCombinesRotations() {
        let rotation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)) // 90 degrees
        let input = SeatMovementInput(
            seatLocalPosition: SIMD3<Float>(0, 0, 1),
            viewerAdjustment: .zero,
            verticalOffset: 0,
            userRotationDegrees: 45,
            seatRotation: rotation
        )
        
        let result = SeatMovementCalculator.calculate(input: input)
        // yaw extraction returns -90 in current implementation, so combined = -45
        XCTAssertEqual(result.combinedRotationDegrees, -45, accuracy: 0.01)
    }
}
