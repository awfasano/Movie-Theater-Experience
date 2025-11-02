import XCTest
@testable import Movie_Theater_Experience

final class BookmarkManagerTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private let suiteName = "BookmarkManagerTests"
    private let storageKey = "test_bookmarks"
    
    override func setUp() {
        super.setUp()
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite for tests")
            return
        }
        userDefaults = defaults
        defaults.removePersistentDomain(forName: suiteName)
    }
    
    override func tearDown() {
        userDefaults?.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }
    
    func testAddingBookmarkPersistsIt() {
        guard let defaults = userDefaults else {
            XCTFail("UserDefaults not configured")
            return
        }
        let manager = BookmarkManager(userDefaults: defaults, storageKey: storageKey)
        let url = URL(string: "https://example.com")!
        
        manager.addBookmark(name: "Example", url: url)
        
        XCTAssertEqual(manager.bookmarks.count, 1)
        XCTAssertEqual(manager.bookmarks.first?.name, "Example")
        XCTAssertEqual(manager.bookmarks.first?.url, url)
        
        let reloaded = BookmarkManager(userDefaults: defaults, storageKey: storageKey)
        XCTAssertEqual(reloaded.bookmarks, manager.bookmarks)
    }
    
    func testRemovingBookmarkUpdatesStorage() {
        guard let defaults = userDefaults else {
            XCTFail("UserDefaults not configured")
            return
        }
        let manager = BookmarkManager(userDefaults: defaults, storageKey: storageKey)
        manager.addBookmark(name: "First", url: URL(string: "https://first.com")!)
        manager.addBookmark(name: "Second", url: URL(string: "https://second.com")!)
        
        manager.removeBookmark(at: IndexSet(integer: 0))
        
        XCTAssertEqual(manager.bookmarks.count, 1)
        XCTAssertEqual(manager.bookmarks.first?.name, "Second")
        
        let reloaded = BookmarkManager(userDefaults: defaults, storageKey: storageKey)
        XCTAssertEqual(reloaded.bookmarks.count, 1)
        XCTAssertEqual(reloaded.bookmarks.first?.name, "Second")
    }
}
