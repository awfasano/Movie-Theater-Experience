import SwiftUI

// MARK: - Main View
struct StoriesListView: View {
    @StateObject private var firebaseService = FirebaseStoryService()
    
    // Read the shared AppModel from the environment instead of passing a spaceId.
    @Environment(AppModel.self) private var appModel
    
    // Animation states
    @State private var isContentVisible = false
    @State private var loadingOpacity: Double = 1.0
    @State private var visibleStoryIndices: Set<Int> = []

    var body: some View {
        // Use the optional `selectedSpace` from the AppModel to drive the view
        if let space = appModel.selectedSpace, let spaceId = space.id {
            NavigationStack {
                ZStack {
                    // Background
                    Color(.systemBackground)
                        .ignoresSafeArea()
                    
                    // Content
                    if firebaseService.isLoading && firebaseService.stories.isEmpty {
                        loadingView
                    } else if !firebaseService.stories.isEmpty {
                        storiesScrollView
                    } else {
                        // Handles the empty or error state after loading is complete
                        emptyOrErrorStateView
                    }
                }
                .navigationTitle(space.spaceName) // Use the space name for the title
                .navigationDestination(for: Story.self) { story in
                    InteractiveStoryView(story: story)
                }
                // This task automatically re-runs when the selected space's ID changes.
                .task(id: spaceId) {
                    await loadStories(for: spaceId)
                }
            }
        } else {
            // A placeholder view when no space is selected.
            noSpaceSelectedView
        }
    }
    
    // MARK: - Child Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primary))
            Text("Loading Stories...")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
    
    private var storiesScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                ForEach(Array(firebaseService.stories.enumerated()), id: \.element) { index, story in
                    NavigationLink(value: story) {
                        StoryRowView(story: story)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
        .transition(.opacity)
    }
    
    private var emptyOrErrorStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: firebaseService.error != nil ? "wifi.exclamationmark" : "book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(firebaseService.error != nil ? "Failed to Load Stories" : "No Stories Found")
                .font(.title3)
                .foregroundStyle(.secondary)

            if firebaseService.error != nil, let space = appModel.selectedSpace, let spaceId = space.id {
                Button {
                    Task {
                        await loadStories(for: spaceId)
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .transition(.opacity)
    }
    
    private var noSpaceSelectedView: some View {
        VStack(spacing: 15) {
            Image(systemName: "books.vertical")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("No Space Selected")
                .font(.title)
            Text("Select a space from the browser to see its stories.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    private func loadStories(for spaceId: String) async {
        // Reset state for the new space
        firebaseService.clearCache()
        
        // Fetch stories using the dynamic spaceId
        await firebaseService.fetchStories(fromSpaceId: spaceId)
    }
}
