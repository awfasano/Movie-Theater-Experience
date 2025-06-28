
import XCTest
import AVFoundation
import RealityKit
@testable import Movie_Theater_Experience

@MainActor
class VideoPlayerManagerTests: XCTestCase {

    var videoPlayerManager: VideoPlayerManager!
    var mockLightingManager: MockTheatreLightingManager!
    var mockSpatialAudioManager: MockSpatialAudioManager!
    var placeholderScreenEntity: ModelEntity!

    override func setUp() {
        super.setUp()
        videoPlayerManager = VideoPlayerManager()
        mockLightingManager = MockTheatreLightingManager()
        mockSpatialAudioManager = MockSpatialAudioManager()
        videoPlayerManager.setLightingManager(mockLightingManager)
        videoPlayerManager.setSpatialAudioManager(mockSpatialAudioManager)
        placeholderScreenEntity = ModelEntity()
    }

    override func tearDown() {
        videoPlayerManager = nil
        mockLightingManager = nil
        mockSpatialAudioManager = nil
        placeholderScreenEntity = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(videoPlayerManager)
    }

    func testSetLightingManager() {
        let newLightingManager = MockTheatreLightingManager()
        videoPlayerManager.setLightingManager(newLightingManager)
        // We can't directly test the property, but we can test its effect.
        // For example, by calling a method that uses it.
    }

    func testSetSpatialAudioManager() {
        let newSpatialAudioManager = MockSpatialAudioManager()
        videoPlayerManager.setSpatialAudioManager(newSpatialAudioManager)
        // Similar to the lighting manager, we'd test this by its effect.
    }

    func testConfigureVideo() async {
        let videoURL = Bundle(for: type(of: self)).url(forResource: "blank", withExtension: "mp4")!
        let player = await videoPlayerManager.configureVideo(for: placeholderScreenEntity, videoURL: videoURL)
        
        XCTAssertNotNil(player)
        XCTAssertNotNil(videoPlayerManager.player)
        XCTAssertTrue(videoPlayerManager.isPlaybackReady)
    }

    func testClearAllResources() {
        videoPlayerManager.clearAllResources()
        XCTAssertNil(videoPlayerManager.player)
        XCTAssertFalse(videoPlayerManager.isPlaybackReady)
    }
}

class MockTheatreLightingManager: TheatreLightingManager {
    var startMovieLightingEffectCalled = false
    var stopMovieLightingEffectCalled = false

    override func startMovieLightingEffect() async {
        startMovieLightingEffectCalled = true
    }

    override func stopMovieLightingEffect() async {
        stopMovieLightingEffectCalled = true
    }
}

class MockSpatialAudioManager: SpatialAudioManager {
    var configureAudioForVideoCalled = false

    override func configureAudioForVideo(player: AVPlayer?) {
        configureAudioForVideoCalled = true
    }
}
