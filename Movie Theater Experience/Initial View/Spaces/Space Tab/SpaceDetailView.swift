//
//  SpaceDetailView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/2/25.
//

import Foundation
import SwiftUI

/// A detailed view for a single space
struct SpaceDetailView: View {
    let space: SpaceData
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Volumetric view
                    VolumetricSpaceView(space: space, onEnter: {
                        // This closure will be called when the "Enter Space" button is tapped
                        // in VolumetricSpaceView.
                        // We need to open the immersive space here.
                        Task {
                            do {
                                try await openImmersiveSpace(id: appModel.spacesID)
                                print("✅ Immersive space opened successfully from SpaceDetailView")
                            } catch {
                                print("❌ Failed to open immersive space from SpaceDetailView: \(error)")
                            }
                        }
                    })
                        .frame(height: 400)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(space.spaceName)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(space.spaceName)
                            .font(.body)
                        
                        Divider()
                        
                        if let tags = space.tags, !tags.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Tags")
                                    .font(.headline)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            
                            Divider()
                        }
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Created")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(formattedDate(space.lastModified))
                                    .font(.callout)
                            }
                            
                            Spacer()
                            
                            Link(destination: URL(string: space.usdzURL)!) {
                                Label("View Original", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.bordered)
                            .disabled(URL(string: space.usdzURL) == nil)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Space Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

