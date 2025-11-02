import XCTest
@testable import Movie_Theater_Experience

final class StoryTests: XCTestCase {
    func testComputedURLsReturnFirstValidEntries() {
        let story = Story(
            id: "story-1",
            name: "Sample Story",
            description: "Desc",
            author: "Author",
            instructions: "Do this",
            voice: "Puck",
            preview: "https://example.com/preview.png",
            audio: "https://example.com/audio.mp3",
            videos: ["https://example.com/video.mp4"]
        )
        
        XCTAssertEqual(story.videoURL, URL(string: "https://example.com/video.mp4"))
        XCTAssertEqual(story.audioURL, URL(string: "https://example.com/audio.mp3"))
        XCTAssertEqual(story.previewURL, URL(string: "https://example.com/preview.png"))
    }
    
    func testComputedURLsHandleInvalidStrings() {
        let story = Story(
            id: "story-2",
            name: "Invalid URLs",
            description: "",
            author: "",
            instructions: "",
            voice: "",
            preview: "not a url",
            audio: "also not a url",
            videos: ["still not a url"]
        )
        
        XCTAssertNil(story.videoURL)
        XCTAssertNil(story.audioURL)
        XCTAssertNil(story.previewURL)
    }
    
    func testEquatableReliesOnDocumentIDAndFields() {
        var storyA = Story(
            id: "id-1",
            name: "A",
            description: "Desc",
            author: "Author",
            instructions: "Inst",
            voice: "Voice",
            preview: "preview",
            audio: "audio",
            videos: []
        )
        var storyB = storyA
        XCTAssertEqual(storyA, storyB)
        
        storyB.name = "Different"
        XCTAssertNotEqual(storyA, storyB)
    }
}
