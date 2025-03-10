//
//  OccupancyView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 2/5/25.
//

import Foundation

// View for displaying occupancy information
struct OccupancyView: View {
    let space: IntroSpace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Occupancy")
                .font(.headline)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("\(space.currentOccupancy)")
                        .font(.title)
                        .foregroundColor(.primary)
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("\(space.maxOccupancy)")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("Maximum")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Occupancy progress bar
            ProgressView(
                value: Double(space.currentOccupancy),
                total: Double(space.maxOccupancy)
            )
            .tint(occupancyColor)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
    
    private var occupancyColor: Color {
        let percentage = Double(space.currentOccupancy) / Double(space.maxOccupancy)
        switch percentage {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }
}
