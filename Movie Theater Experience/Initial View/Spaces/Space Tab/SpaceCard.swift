import SwiftUI

struct SpaceCard: View {
    let space: SpaceData
    let isHighlighted: Bool // NEW: Parameter to control highlighting
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
    
    // NEW: Computed properties for highlighting effects
    private var cardScale: CGFloat {
        isHighlighted ? 1.08 : (isHovering ? 1.03 : 1.0)
    }
    
    private var cardOpacity: Double {
        isHighlighted ? 1.0 : (isHovering ? 0.95 : 0.9)
    }
    
    private var shadowRadius: CGFloat {
        isHighlighted ? 25 : (isHovering ? 15 : 5)
    }
    
    private var shadowOpacity: Double {
        isHighlighted ? 0.8 : (isHovering ? 0.4 : 0.2)
    }
    
    private var borderColor: Color {
        isHighlighted ? .blue : .clear
    }
    
    private var borderWidth: CGFloat {
        isHighlighted ? 4 : 0
    }
    
    private var glowEffect: Color {
        isHighlighted ? .blue.opacity(0.3) : .clear
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
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.thinMaterial)
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
                
                // NEW: Highlight indicator overlay
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(height: 180)
            // The .clipped() modifier ensures the image never draws outside the frame.
            .clipped()
            .overlay(alignment: .topTrailing) {
                // Info Circle Button
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
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .background(
            // Glow effect for highlighted state
            RoundedRectangle(cornerRadius: 24)
                .fill(glowEffect)
                .blur(radius: 10)
                .scaleEffect(1.1)
        )
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
        .hoverEffect(.highlight) // Use .highlight for better gaze feedback
        .onContinuousHover { phase in
            switch phase {
            case .active(_):
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isHovering = true
                }
            case .ended:
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isHovering = false
                }
            }
        }
        .shadow(
            color: .black.opacity(shadowOpacity),
            radius: shadowRadius
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHighlighted)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
    }
}

// MARK: - Convenience Initializer for Backward Compatibility
extension SpaceCard {
    init(space: SpaceData, onInfoTapped: @escaping () -> Void) {
        self.space = space
        self.isHighlighted = false
        self.onInfoTapped = onInfoTapped
    }
}
