
import XCTest
import RealityKit
@testable import Movie_Theater_Experience

@MainActor
class SpatialAudioLoaderTests: XCTestCase {

    var audioLoader: SpatialAudioLoader!
    var appModel: AppModel!

    override func setUp() {
        super.setUp()
        audioLoader = SpatialAudioLoader()
        appModel = AppModel()
        audioLoader.attach(appModel: appModel)
    }

    override func tearDown() {
        audioLoader = nil
        appModel = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(audioLoader)
    }

    func testSetSongs() {
        let songs = [Song(id: "1", song: "Song 1", artist: "Artist 1", artworkURL: "", audioURL: "", uploadedAt: nil)]
        audioLoader.setSongs(songs)
        // Can't directly access songs, but can test behavior
    }

    func testNextAndPreviousTrack() {
        let songs = [
            Song(id: "1", song: "Song 1", artist: "Artist 1", artworkURL: "", audioURL: "", uploadedAt: nil),
            Song(id: "2", song: "Song 2", artist: "Artist 2", artworkURL: "", audioURL: "", uploadedAt: nil)
        ]
        audioLoader.setSongs(songs)
        
        XCTAssertEqual(audioLoader.currentTrackIndex, 0)
        audioLoader.nextTrack()
        XCTAssertEqual(audioLoader.currentTrackIndex, 1)
        audioLoader.nextTrack()
        XCTAssertEqual(audioLoader.currentTrackIndex, 0)
        
        audioLoader.previousTrack()
        XCTAssertEqual(audioLoader.currentTrackIndex, 1)
    }

    func testSetVolume() {
        audioLoader.setVolume(0.5)
        XCTAssertEqual(audioLoader.masterVolume, 0.5, accuracy: 0.01)
        
        audioLoader.setVolume(1.5)
        XCTAssertEqual(audioLoader.masterVolume, 1.0, accuracy: 0.01)
        
        audioLoader.setVolume(-0.5)
        XCTAssertEqual(audioLoader.masterVolume, 0.0, accuracy: 0.01)
    }

    func testFindSpeakers() {
        let root = Entity()
        let speaker1 = Entity()
        speaker1.name = "speaker_1"
        let speaker2 = Entity()
        speaker2.name = "speaker_2"
        let notASpeaker = Entity()
        notASpeaker.name = "something_else"
        
        root.addChild(speaker1)
        root.addChild(notASpeaker)
        notASpeaker.addChild(speaker2)
        
        let speakers = audioLoader.findSpeakers(in: root)
        XCTAssertEqual(speakers.count, 2)
    }

    func testLinearToDB() {
        XCTAssertEqual(audioLoader.linearToDB(1.0), 0.0, accuracy: 0.01)
        XCTAssertEqual(audioLoader.linearToDB(0.5), -6.02, accuracy: 0.01)
        XCTAssertEqual(audioLoader.linearToDB(0.0), -80.0, accuracy: 0.01)
    }
}
