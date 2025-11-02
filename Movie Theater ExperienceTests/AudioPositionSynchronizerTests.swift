import XCTest
import RealityKit
@testable import Movie_Theater_Experience

final class AudioPositionSynchronizerTests: XCTestCase {
    func testBaseVolumeAppliedWhenEntityAtOrigin() {
        let entity = Entity()
        entity.transform.translation = SIMD3<Float>(0, 0, 0)
        let synchronizer = AudioPositionSynchronizer(entity: entity)
        let player = MockAudioPlayer()
        
        synchronizer.startTracking(playerController: player)
        XCTAssertEqual(player.volume, 1.0, accuracy: 0.001)
        synchronizer.stopTracking()
    }
    
    func testRelativePositionDistanceAppliesAttenuation() {
        let entity = Entity()
        entity.transform.translation = SIMD3<Float>(0, 0, 0)
        let synchronizer = AudioPositionSynchronizer(entity: entity)
        let player = MockAudioPlayer()
        synchronizer.startTracking(playerController: player)
        
        synchronizer.updateRelativePosition(SIMD3<Float>(10, 0, 0))
        
        let expectedVolume = 1.0 / (1.0 + 0.70 * (100.0 / 100.0))
        XCTAssertEqual(player.volume, Float(expectedVolume), accuracy: 0.001)
        synchronizer.stopTracking()
    }
    
    func testOutOfRangeRelativePositionMutesPlayer() {
        let entity = Entity()
        entity.transform.translation = SIMD3<Float>(0, 0, 0)
        let synchronizer = AudioPositionSynchronizer(entity: entity)
        let player = MockAudioPlayer()
        synchronizer.startTracking(playerController: player)
        
        synchronizer.updateRelativePosition(SIMD3<Float>(20, 0, 0))
        XCTAssertEqual(player.volume, 0, accuracy: 0.0001)
        synchronizer.stopTracking()
    }
}

private final class MockAudioPlayer: AudioPlayerControlling {
    var volume: Float = 0
}
