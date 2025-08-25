import SwiftUI

struct SpaceCard: View {
    let space: SpaceData
    var isHighlighted: Bool = false
    var onInfoTapped: () -> Void
    var onCardTapped: () -> Void
    
    @Environment(\.gazeActive) private var gazeActive
    @State private var showAttribution = false
    
    private let corner: CGFloat = 24
    private let cardWidth: CGFloat = 320  // Fixed width for consistency
    private let cardHeight: CGFloat = 280  // Fixed total height
    private let imageHeight: CGFloat = 160  // Consistent image height
    
    private var titleGradient: LinearGradient {
        LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        ZStack {
            // Main card content with fixed dimensions
            VStack(spacing: 0) {
                // Image section with overlay gradient
                ZStack(alignment: .bottomLeading) {
                    // Background image
                    Group {
                        if let url = URL(string: space.thumbnailURL ?? "") {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure:
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Image(systemName: "photo.fill")
                                                .font(.largeTitle)
                                                .foregroundStyle(.secondary)
                                        )
                                case .empty:
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(ProgressView())
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Image(systemName: "cube.transparent.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                )
                        }
                    }
                    .frame(width: cardWidth, height: imageHeight)
                    .clipped()
                    
                    // Gradient overlay for text readability
                    LinearGradient(
                        colors: [
                            .black.opacity(0.8),
                            .black.opacity(0.5),
                            .clear
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: imageHeight * 0.6)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    
                    // Title overlaid on image
                    Text(space.spaceName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
                .frame(width: cardWidth, height: imageHeight)
                
                // Content section with fixed height
                VStack(alignment: .leading, spacing: 8) {
                    // Description
                    Text(space.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer(minLength: 4)
                    
                    // Bottom row with occupancy and tags
                    VStack(alignment: .leading, spacing: 8) {
                        // Occupancy indicator
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            
                            Text("\(space.currentUserCount) users")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Circle()
                                .fill(occupancyColor)
                                .frame(width: 8, height: 8)
                            
                            Spacer()
                        }
                        
                        // Tags if available
                        if let tags = space.tags, !tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(tags.prefix(3), id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule()
                                                .fill(Color.cyan.opacity(0.15))
                                        )
                                        .foregroundColor(.cyan)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(width: cardWidth, height: cardHeight - imageHeight)
                .background(.ultraThinMaterial)
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .stroke(
                        isHighlighted || gazeActive
                            ? titleGradient
                            : LinearGradient(colors: [Color.white.opacity(0.1)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: isHighlighted || gazeActive ? 2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .shadow(color: .black.opacity(0.2), radius: isHighlighted ? 12 : 6, x: 0, y: isHighlighted ? 8 : 4)
            .shadow(color: gazeActive ? .cyan.opacity(0.3) : .clear, radius: 20)
            .animation(.easeInOut(duration: 0.25), value: isHighlighted)
            .animation(.easeInOut(duration: 0.3), value: gazeActive)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: corner))
            .interactiveCardHover(cornerRadius: corner)
            .onTapGesture {
                onCardTapped()
            }
            
            // Info button overlay - positioned consistently
            VStack {
                HStack {
                    Spacer()
                    
                    // Info button
                    Button(action: {
                        showAttribution = true
                        onInfoTapped()
                    }) {
                        ZStack {
                            Circle()
                                .fill(.regularMaterial)
                                .frame(width: 32, height: 32)
                            
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                                .symbolRenderingMode(.monochrome)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                    .hoverEffect(.highlight)
                    .padding(10)
                }
                Spacer()
            }
            .frame(width: cardWidth, height: cardHeight)
            .allowsHitTesting(true)
        }
        .frame(width: cardWidth, height: cardHeight)  // Enforce consistent size
        .popover(isPresented: $showAttribution, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Attribution")
                        .font(.headline)
                    Spacer()
                    Button("Done") {
                        showAttribution = false
                    }
                    .buttonStyle(.borderless)
                }
                
                Text(space.attributions ?? "No attribution information available.")
                    .font(.body)
            }
            .padding()
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
        }
    }
    
    private var occupancyColor: Color {
        switch space.occupancyPercentage {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }
}
