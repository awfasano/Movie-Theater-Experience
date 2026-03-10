//
//  AmbientSpaceCard.swift
//  Movie Theater Experience
//
//  Created for Ambient Focus Rooms feature.
//

import SwiftUI

struct AmbientSpaceCard: View {
    let space: SpaceData

    /// Infer a soundscape icon from the space's tags.
    private var soundscapeIcon: String {
        guard let tags = space.tags else { return "sparkles" }
        let lowered = tags.map { $0.lowercased() }
        if lowered.contains("rain") { return "cloud.rain.fill" }
        if lowered.contains("fireplace") { return "flame.fill" }
        if lowered.contains("ocean") { return "water.waves" }
        if lowered.contains("forest") { return "leaf.fill" }
        if lowered.contains("cafe") || lowered.contains("café") { return "cup.and.saucer.fill" }
        if lowered.contains("space") { return "sparkles" }
        return "waveform"
    }

    /// Derive a mood label from tags — "Focus" or "Relax".
    private var moodLabel: String {
        guard let tags = space.tags else { return "Focus" }
        let lowered = tags.map { $0.lowercased() }
        if lowered.contains("relax") || lowered.contains("relaxation") || lowered.contains("calm") {
            return "Relax"
        }
        return "Focus"
    }

    /// Accent color for the mood label.
    private var moodColor: Color {
        moodLabel == "Relax" ? .teal : .indigo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack(alignment: .bottomLeading) {
                if let thumbnailURL = space.thumbnailURL, let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                                .overlay {
                                    ProgressView()
                                        .tint(.white)
                                }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .overlay(
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.6)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        case .failure:
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                                .overlay {
                                    Image(systemName: "moon.stars.fill")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.7), Color.indigo.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Image(systemName: "moon.stars.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray.opacity(0.6))
                        }
                }

                // Soundscape icon overlay
                HStack(spacing: 6) {
                    Image(systemName: soundscapeIcon)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))

                    Text(moodLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(moodColor.opacity(0.6))
                .clipShape(Capsule())
                .padding(8)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Space information
            VStack(alignment: .leading, spacing: 4) {
                Text(space.spaceName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(space.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.bottom, 4)

                // Tags display (excluding "ambient" since it's implied)
                if let tags = space.tags?.filter({ $0.lowercased() != "ambient" }), !tags.isEmpty {
                    HStack {
                        ForEach(Array(tags.prefix(2)), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(moodColor.opacity(0.15))
                                .foregroundColor(moodColor)
                                .clipShape(Capsule())
                        }

                        if tags.count > 2 {
                            Text("+\(tags.count - 2)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

struct AmbientSpaceCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            AmbientSpaceCard(space: SpaceData(
                spaceName: "Rainy Study Room",
                description: "A cozy room with the sound of rain on the window",
                lastModified: Date(),
                usdzURL: "https://example.com/rain.usdz",
                thumbnailURL: nil,
                tags: ["ambient", "rain", "Focus"],
                currentUserCount: 3,
                maxUserCount: 50
            ))

            AmbientSpaceCard(space: SpaceData(
                spaceName: "Ocean Sunset",
                description: "Relax by the shore with gentle waves",
                lastModified: Date(),
                usdzURL: "https://example.com/ocean.usdz",
                thumbnailURL: nil,
                tags: ["ambient", "ocean", "relax"],
                currentUserCount: 7,
                maxUserCount: 50
            ))
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
