import Foundation

struct Bookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    let url: URL
}

class BookmarkManager: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    private let bookmarksKey: String
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard, storageKey: String = "bookmarks") {
        self.userDefaults = userDefaults
        self.bookmarksKey = storageKey
        loadBookmarks()
    }

    func addBookmark(name: String, url: URL) {
        let bookmark = Bookmark(name: name, url: url)
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func removeBookmark(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        saveBookmarks()
    }

    private func saveBookmarks() {
        guard let encoded = try? JSONEncoder().encode(bookmarks) else { return }
        userDefaults.set(encoded, forKey: bookmarksKey)
    }

    private func loadBookmarks() {
        guard let data = userDefaults.data(forKey: bookmarksKey),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            bookmarks = []
            return
        }
        bookmarks = decoded
    }
}
