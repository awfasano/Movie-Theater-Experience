//
//  OccupancyProgressView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 2/5/25.
//

import Foundation
import SwiftUI

struct OccupancyProgressView: View {
    let currentOccupancy: Int
    let maxOccupancy: Int
    
    /// Calculate the occupancy percentage as a value between 0 and 1.
    private var occupancyPercentage: Double {
        guard maxOccupancy > 0 else { return 0 }
        return Double(currentOccupancy) / Double(maxOccupancy)
    }
    
    /// Choose a color based on the occupancy percentage.
    private var occupancyColor: Color {
        switch occupancyPercentage {
        case ..<0.5:
            return .green
        case ..<0.8:
            return .yellow
        default:
            return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header text
            Text("Occupancy")
                .font(.headline)
            
            // Display the current and maximum occupancy
            HStack {
                VStack(alignment: .leading) {
                    Text("\(currentOccupancy)")
                        .font(.title)
                        .foregroundColor(.primary)
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(maxOccupancy)")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("Maximum")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // The progress bar
            ProgressView(value: occupancyPercentage)
                .progressViewStyle(LinearProgressViewStyle(tint: occupancyColor))
                .animation(.easeInOut, value: occupancyPercentage)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct OccupancyProgressView_Previews: PreviewProvider {
    static var previews: some View {
        OccupancyProgressView(currentOccupancy: 25, maxOccupancy: 50)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
