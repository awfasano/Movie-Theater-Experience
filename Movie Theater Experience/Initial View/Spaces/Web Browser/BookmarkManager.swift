import Foundation

struct Bookmark: Identifiable, Codable {
    var id = UUID()
    let name: String
    let url: URL
}

class BookmarkManager: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    private let bookmarksKey = "bookmarks"

    init() {
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
        if let encoded = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(encoded, forKey: bookmarksKey)
        }
    }

    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: bookmarksKey) {
            if let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
                bookmarks = decoded
            }
        }
    }
}
