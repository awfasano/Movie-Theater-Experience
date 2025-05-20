import SwiftUI

struct StoryRowView: View {
    let story: Story
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: story) {
            ZStack(alignment: .bottomLeading) {
                // Story image
                AsyncImage(url: story.previewURL) { phase in
                    switch phase {
                    case .empty:
                        Color.gray.opacity(0.1)
                            .frame(height: 200)
                            .overlay(
                                ProgressView()
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .clipped()
                    case .failure:
                        Color.gray.opacity(0.3)
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }

                // Dark gradient at bottom for text
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.7), .clear]),
                    startPoint: .bottom,
                    endPoint: .center
                )
                .frame(height: 80)

                // Title & description
                VStack(alignment: .leading, spacing: 4) {
                    Text(story.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text(story.description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding()
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(isHovering ? 0.3 : 0.2), radius: isHovering ? 12 : 8, x: 0, y: 4)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .padding(.horizontal)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .buttonStyle(.plain)
        .accentColor(.primary) // remove default highlight
    }
}

struct StoriesListView_Previews: PreviewProvider {
    static var previews: some View {
        StoriesListView()
    }
}
