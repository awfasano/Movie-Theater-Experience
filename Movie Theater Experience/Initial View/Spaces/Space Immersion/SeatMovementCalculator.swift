import Foundation
import simd

struct SeatMovementInput {
    let seatLocalPosition: SIMD3<Float>
    let viewerAdjustment: SIMD3<Float>
    let verticalOffset: Float
    let userRotationDegrees: Float
    let seatRotation: simd_quatf
}

struct SeatMovementResult {
    let anchorPosition: SIMD3<Float>
    let combinedRotation: simd_quatf
    let combinedRotationDegrees: Float
}

enum SeatMovementCalculator {
    static func calculate(input: SeatMovementInput) -> SeatMovementResult {
        let baseAnchor = -input.seatLocalPosition
            - input.viewerAdjustment
            + SIMD3<Float>(0, input.verticalOffset, 0)
        
        let seatYaw = yawDegrees(from: input.seatRotation)
        let combinedDegrees = input.userRotationDegrees + seatYaw
        let combinedRadians = combinedDegrees * .pi / 180
        let combinedRotation = simd_quatf(angle: combinedRadians, axis: SIMD3<Float>(0, 1, 0))
        
        let rotatedAnchor = combinedRotation.act(baseAnchor)
        
        return SeatMovementResult(
            anchorPosition: rotatedAnchor,
            combinedRotation: combinedRotation,
            combinedRotationDegrees: combinedDegrees
        )
    }
    
    static func yawDegrees(from quaternion: simd_quatf) -> Float {
        let matrix = float3x3(quaternion)
        let yaw = atan2(matrix[0][2], matrix[2][2])
        return yaw * 180 / .pi
    }
}
