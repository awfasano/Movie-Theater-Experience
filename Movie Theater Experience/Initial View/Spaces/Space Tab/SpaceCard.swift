import SwiftUI
struct SpaceCard: View {
    let space: SpaceData
    // Add a closure to handle the info button tap.
    var onInfoTapped: () -> Void

    @State private var isHovering = false
    @State private var showAttribution = false

    // MARK: - UI Helpers
    
    private var occupancyColor: Color {
        let percentage = space.occupancyPercentage
        switch percentage {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }
    
    private var occupancyText: String {
        let percentage = Int(space.occupancyPercentage * 100)
        return "\(space.currentUserCount)/\(space.maxUserCount) • \(percentage)%"
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Visual Header
            ZStack(alignment: .bottomLeading) {
                // This AsyncImage will fill the entire space allocated to it.
                if let thumbnailURL = space.thumbnailURL, let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo").font(.largeTitle).frame(maxWidth: .infinity, maxHeight: .infinity).background(.thinMaterial)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 60))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.2))
                }
                
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.8), .clear]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(space.spaceName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                    
                    Text(space.description)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
                .padding()
            }
            .frame(height: 180)
            // The .clipped() modifier ensures the image never draws outside the frame.
            .clipped()
            .overlay(alignment: .topTrailing) {
                // NEW: Info Circle Button
                Button(action: { showAttribution.toggle() }) {
                    Label("More Info", systemImage: "info.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain) // Use .plain to avoid default button chrome
                .hoverEffect(.lift)
                .padding(12)
                .popover(isPresented: $showAttribution, arrowEdge: .top) {
                    Text(space.attributions ?? "")
                        .padding()
                        .frame(width: 300)
                        .presentationCompactAdaptation(.popover)
                }
            }
            
            // MARK: Details Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(occupancyText, systemImage: "person.2.fill")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Circle()
                        .fill(occupancyColor)
                        .frame(width: 10, height: 10)
                }
                
                if let tags = space.tags, !tags.isEmpty {
                    HStack {
                        ForEach(Array(tags.prefix(3)), id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.2))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassBackgroundEffect()
        .clipShape(RoundedRectangle(cornerRadius: 24))
        // REMOVED: .scaleEffect to prevent cards from overlapping on hover.
        .hoverEffect(.lift)
        .onHover { hovering in
            withAnimation(.spring()) {
                isHovering = hovering
            }
        }
        .shadow(color: .black.opacity(isHovering ? 0.4 : 0.2), radius: isHovering ? 15 : 5)
        .animation(.spring(), value: isHovering)
    }
}

