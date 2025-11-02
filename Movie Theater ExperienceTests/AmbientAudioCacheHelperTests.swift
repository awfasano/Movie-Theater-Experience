import XCTest
@testable import Movie_Theater_Experience

final class AmbientAudioCacheHelperTests: XCTestCase {
    func testSanitizedFileNameRemovesQueryAndSlashes() {
        let url = URL(string: "https://example.com/audio/ambient/track.mp3?token=123")!
        let sanitized = AmbientAudioCacheHelper.sanitizedFileName(for: url)
        XCTAssertEqual(sanitized, "track.mp3")
    }
    
    func testSanitizedFileNameFallsBackToUUIDWhenEmpty() {
        let url = URL(string: "https://example.com/")!
        let sanitized = AmbientAudioCacheHelper.sanitizedFileName(for: url)
        XCTAssertFalse(sanitized.isEmpty)
        XCTAssertFalse(sanitized.isEmpty)
    }
    
    func testCacheURLResidesInsideAmbientAudioDirectory() {
        let url = URL(string: "https://example.com/audio/track.mp3")!
        let cacheURL = AmbientAudioCacheHelper.cacheURL(for: url)
        
        let cachesDirectory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Spaces/ambient_audio", isDirectory: true)
        
        XCTAssertTrue(cacheURL.path.hasPrefix(cachesDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachesDirectory.path))
        XCTAssertEqual(cacheURL.lastPathComponent, "track.mp3")
    }
}
