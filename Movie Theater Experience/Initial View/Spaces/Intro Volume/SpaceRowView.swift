//
//  SpaceRowView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 2/5/25.
//

import Foundation
import SwiftUICore

struct SpaceRowView: View {
    let space: IntroSpace
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundStyle(isSelected ? .blue : .gray)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.headline)
                Text("\(space.currentOccupancy) people present")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}
