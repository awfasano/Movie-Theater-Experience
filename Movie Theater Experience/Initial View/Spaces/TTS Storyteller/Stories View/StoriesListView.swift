
import SwiftUI

struct StoriesListView: View {
    @StateObject private var firebaseService = FirebaseStoryService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if firebaseService.stories.isEmpty {
                    ProgressView("Loading Stories...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(firebaseService.stories) { story in
                                StoryRowView(story: story)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Stories")
            .navigationDestination(for: Story.self) { story in
                InteractiveStoryView(story: story)
            }
            .onAppear {
                if firebaseService.stories.isEmpty {
                    firebaseService.fetchStories(fromSpaceId: "space bar")
                }
            }
        }
    }
}
