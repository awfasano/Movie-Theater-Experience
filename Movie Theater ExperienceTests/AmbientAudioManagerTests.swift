import XCTest
@testable import Movie_Theater_Experience

final class AmbientAudioManagerTests: XCTestCase {

    func testPercentageToDecibelsClampsZeroAndHundred() {
        XCTAssertEqual(AmbientAudioManager.percentageToDecibels(0), -200)
        XCTAssertEqual(AmbientAudioManager.percentageToDecibels(100), 0)
    }

    func testPercentageToDecibelsMidpoint() {
        XCTAssertEqual(AmbientAudioManager.percentageToDecibels(50), -10)
    }

    func testSanitizedFileNameRemovesPathSeparatorsAndQueries() {
        let url = URL(string: "https://example.com/o/Spaces%2Fambient_audio%2Floop.mp3?alt=media&token=123")!
        let fileName = AmbientAudioCacheHelper.sanitizedFileName(for: url)
        XCTAssertEqual(fileName, "Spaces_ambient_audio_loop.mp3")
        XCTAssertFalse(fileName.contains("/"))
        XCTAssertFalse(fileName.contains("?"))
    }

    func testBuildCacheURLUsesProvidedBaseDirectory() {
        let url = URL(string: "https://example.com/o/Spaces%2Fanother_segment%2Ftest-file.wav")!
        let cacheURL = AmbientAudioCacheHelper.cacheURL(for: url)
        XCTAssertEqual(cacheURL.lastPathComponent, "Spaces_another_segment_test-file.wav")
    }

    func testSanitizedFileNameGeneratesUUIDFallback() {
        let url = URL(string: "https://example.com/resources/")!
        let fileName = AmbientAudioCacheHelper.sanitizedFileName(for: url)

        XCTAssertFalse(fileName.isEmpty)
    }
}
