import XCTest
@testable import Movie_Theater_Experience

final class SongTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let song = Song(
            id: "song-1",
            song: "Title",
            artist: "Artist",
            artworkURL: "https://example.com/art.png",
            audioURL: "https://example.com/audio.mp3",
            uploadedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        
        let data = try JSONEncoder().encode(song)
        let decoded = try JSONDecoder().decode(Song.self, from: data)
        XCTAssertEqual(decoded, song)
    }
}
