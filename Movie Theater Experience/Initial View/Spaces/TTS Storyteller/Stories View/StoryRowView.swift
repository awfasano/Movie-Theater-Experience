import SwiftUI

// MARK: - Story Row View

struct StoryRowView: View {
    let story: Story
    @State private var isHovering = false
    @State private var imageLoadState: ImageLoadState = .loading
    @Environment(\.colorScheme) private var colorScheme
    
    private enum ImageLoadState {
        case loading
        case success(Image)
        case failure
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background for consistent height
            Color(.secondarySystemBackground)
                .frame(height: 200)
                
            // Story image with optimized loading
            imageView
                
            // Gradient overlay
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.7), .clear]),
                startPoint: .bottom,
                endPoint: .center
            )
            .frame(height: 80)
            .allowsHitTesting(false)
                
            // Title & description
            VStack(alignment: .leading, spacing: 4) {
                Text(story.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(story.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            }
            .padding()
        }
        .frame(height: 200)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .shadow(
            color: Color.black.opacity(isHovering ? 0.3 : 0.2),
            radius: isHovering ? 12 : 8,
            x: 0,
            y: 4
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .task {
            await loadImage()
        }
    }
    
    @ViewBuilder
    private var imageView: some View {
        switch imageLoadState {
        case .loading:
            Color.gray.opacity(0.1)
                .overlay(
                    ProgressView()
                        .tint(.white)
                )
                .transition(.opacity)
                
        case .success(let image):
            image
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .clipped()
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
        case .failure:
            Color.gray.opacity(0.3)
                .overlay(
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                )
                .transition(.opacity)
        }
    }
    
    @MainActor
    private func loadImage() async {
        guard let url = story.previewURL else {
            withAnimation(.easeOut(duration: 0.3)) {
                imageLoadState = .failure
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let uiImage = UIImage(data: data) {
                withAnimation(.easeOut(duration: 0.3)) {
                    imageLoadState = .success(Image(uiImage: uiImage))
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    imageLoadState = .failure
                }
            }
        } catch {
            withAnimation(.easeOut(duration: 0.3)) {
                imageLoadState = .failure
            }
        }
    }
}

// MARK: - Custom Button Style

struct StoryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0))
                    .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            )
    }
}
