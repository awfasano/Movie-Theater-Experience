//
//  SpaceDrawingHandPoseProvider.swift
//  Movie Theater Experience
//
//  Created by GPT-5 Codex on 3/16/25.
//

import Foundation
import ARKit
import simd

@MainActor
final class SpaceDrawingHandPoseProvider {
    struct Sample {
        enum Hand {
            case left
            case right
        }
        
        let position: SIMD3<Float>
        let hand: Hand
        let isIndexExtended: Bool
    }
    
    private let session = ARKitSession()
    private var handTracking: HandTrackingProvider?
    private var trackingTask: Task<Void, Never>?
    private var onUpdate: (@MainActor (Sample) -> Void)?
    
    private(set) var lastKnownWorldPosition: SIMD3<Float>?
    private(set) var lastUpdateTimestamp: TimeInterval = 0
    private var lastRightHandUpdate: TimeInterval = 0
    
    func start(onUpdate: @escaping @MainActor (Sample) -> Void) {
        self.onUpdate = onUpdate
        guard trackingTask == nil else { return }
        let provider = HandTrackingProvider()
        handTracking = provider
        trackingTask = Task {
            await runSession(with: provider)
        }
    }
    
    func stop() {
        trackingTask?.cancel()
        trackingTask = nil
        onUpdate = nil
        Task {
            await session.stop()
        }
        handTracking = nil
    }
    
    private func runSession(with provider: HandTrackingProvider) async {
        do {
            let status = await session.requestAuthorization(for: [.handTracking])
            guard let handStatus = status[.handTracking], handStatus == .allowed else {
                print("⚠️ SpaceDrawingHandPoseProvider: hand tracking permission not granted.")
                return
            }
            try await session.run([provider])
        } catch {
            print("⚠️ SpaceDrawingHandPoseProvider failed to start: \(error)")
            return
        }
        
        for await update in provider.anchorUpdates {
            guard !Task.isCancelled else { break }
            guard let handAnchor = update.anchor as? HandAnchor else { continue }
            
            let now = CFAbsoluteTimeGetCurrent()
            if handAnchor.chirality != .right, now - lastRightHandUpdate < 0.1 {
                continue
            }
            
            guard let sample = makeSample(from: handAnchor) else { continue }
            
            switch sample.hand {
            case .right:
                lastRightHandUpdate = now
            case .left:
                break
            }
            
            lastKnownWorldPosition = sample.position
            lastUpdateTimestamp = now
            onUpdate?(sample)
        }
    }
    
    private func makeSample(from handAnchor: HandAnchor) -> Sample? {
        guard let skeleton = handAnchor.handSkeleton else { return nil }
        
        let tipJoint = skeleton.joint(.indexFingerTip)
        let intermediateBaseJoint = skeleton.joint(.indexFingerIntermediateBase)
        let intermediateTipJoint = skeleton.joint(.indexFingerIntermediateTip)
        let knuckleJoint = skeleton.joint(.indexFingerKnuckle)
        
        guard tipJoint.isTracked,
              intermediateBaseJoint.isTracked,
              intermediateTipJoint.isTracked,
              knuckleJoint.isTracked else {
            return nil
        }
        
        let tipPosition = worldPosition(for: tipJoint, relativeTo: handAnchor)
        let intermediateBasePosition = worldPosition(for: intermediateBaseJoint, relativeTo: handAnchor)
        let intermediateTipPosition = worldPosition(for: intermediateTipJoint, relativeTo: handAnchor)
        let knucklePosition = worldPosition(for: knuckleJoint, relativeTo: handAnchor)
        
        let proximalVector = intermediateBasePosition - knucklePosition
        let distalVector = tipPosition - intermediateTipPosition
        guard simd_length_squared(proximalVector) > 1e-6,
              simd_length_squared(distalVector) > 1e-6 else {
            return nil
        }
        
        let proximalDirection = simd_normalize(proximalVector)
        let distalDirection = simd_normalize(distalVector)
        let alignment = simd_dot(proximalDirection, distalDirection)
        
        var thumbDistance: Float = .greatestFiniteMagnitude
        let thumbJoint = skeleton.joint(.thumbTip)
        if thumbJoint.isTracked {
            let thumbPosition = worldPosition(for: thumbJoint, relativeTo: handAnchor)
            thumbDistance = simd_distance(tipPosition, thumbPosition)
        }
        
        let isStraight = alignment > 0.82
        let isSeparatedFromThumb = thumbDistance > 0.04
        let isIndexExtended = isStraight && isSeparatedFromThumb
        
        let hand: Sample.Hand = handAnchor.chirality == .left ? .left : .right
        
        return Sample(
            position: tipPosition,
            hand: hand,
            isIndexExtended: isIndexExtended
        )
    }
    
    private func worldPosition(for joint: HandSkeleton.Joint, relativeTo handAnchor: HandAnchor) -> SIMD3<Float> {
        let transform = handAnchor.originFromAnchorTransform * joint.anchorFromJointTransform
        return SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }
}
