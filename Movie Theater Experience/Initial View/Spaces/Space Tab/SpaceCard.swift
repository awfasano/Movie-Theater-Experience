//
//  SpaceCard.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/2/25.
//

import SwiftUI

struct SpaceCard: View {
    let space: SpaceData
    
    // Helper computed properties for UI
    private var occupancyColor: Color {
        let percentage = space.occupancyPercentage
        switch percentage {
        case ..<0.5: return .green // Low occupancy
        case ..<0.8: return .yellow // Medium occupancy
        case _: return .red // High occupancy
        }
    }
    
    private var occupancyText: String {
        let percentage = Int(space.occupancyPercentage * 100)
        return "\(space.currentUserCount)/\(space.maxUserCount) • \(percentage)%"
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Thumbnail or placeholder
            ZStack(alignment: .topTrailing) {
                // Image container
                if let thumbnailURL = space.thumbnailURL, let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay {
                                    ProgressView()
                                }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "cube.transparent")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        }
                }
                
                // Occupancy badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(occupancyColor)
                        .frame(width: 8, height: 8)
                    
                    Text(occupancyText)
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding(8)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Space information
            VStack(alignment: .leading, spacing: 4) {
                Text(space.spaceName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(space.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.bottom, 4)
                
                // User activity indicator
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(space.currentUserCount) active users")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Tags display
                if let tags = space.tags, !tags.isEmpty {
                    HStack {
                        ForEach(Array(tags.prefix(2)), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
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
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }
}

// Preview provider for SwiftUI canvas
struct SpaceCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            // Low occupancy
            SpaceCard(space: SpaceData(
                spaceName: "Movie Theater",
                description: "A cozy virtual cinema for movie nights",
                lastModified: Date(),
                usdzURL: "https://example.com/theater.usdz",
                thumbnailURL: nil,
                tags: ["Movies", "Entertainment"],
                currentUserCount: 5,
                maxUserCount: 30
            ))
            
            // Medium occupancy
            SpaceCard(space: SpaceData(
                spaceName: "Concert Hall",
                description: "Live music experience",
                lastModified: Date(),
                usdzURL: "https://example.com/concert.usdz",
                thumbnailURL: nil,
                tags: ["Music", "Entertainment"],
                currentUserCount: 75,
                maxUserCount: 100
            ))
            
            // High occupancy
            SpaceCard(space: SpaceData(
                spaceName: "Virtual Cafe",
                description: "Hang out and chat",
                lastModified: Date(),
                usdzURL: "https://example.com/cafe.usdz",
                thumbnailURL: nil,
                tags: ["Social", "Relaxation"],
                currentUserCount: 18,
                maxUserCount: 20
            ))
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
