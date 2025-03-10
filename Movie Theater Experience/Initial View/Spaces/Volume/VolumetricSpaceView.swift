import Foundation
import RealityKitContent
import RealityKit
import SwiftUI
import Combine

/// A view that displays a single volumetric space
struct VolumetricSpaceView: View {
    let space: SpaceData
    @StateObject private var viewModel = VolumetricSpaceViewModel()
    
    var body: some View {
        ZStack {
            if let entity = viewModel.entity {
                RealityView { content in
                    content.add(entity)
                } update: { content in
                    // Update content if needed
                }
                .gesture(
                    DragGesture()
                        .onChanged { _ in /* Handle rotation if needed */ }
                )
            } else if viewModel.isLoading {
                ProgressView("Loading space...")
            } else if let error = viewModel.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Failed to load")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Retry") {
                        viewModel.loadSpace(space)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(height: 300)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .shadow(radius: 4)
        .onAppear {
            viewModel.loadSpace(space)
        }
    }
}
