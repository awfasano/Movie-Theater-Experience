import SwiftUI
import WebKit

struct BookmarksView: View {
    @ObservedObject var bookmarkManager: BookmarkManager
    @Binding var webView: WKWebView
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(bookmarkManager.bookmarks) {
                    bookmark in
                    Button(action: {
                        webView.load(URLRequest(url: bookmark.url))
                        dismiss()
                    }) {
                        Text(bookmark.name)
                    }
                }
                .onDelete(perform: bookmarkManager.removeBookmark)
            }
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
