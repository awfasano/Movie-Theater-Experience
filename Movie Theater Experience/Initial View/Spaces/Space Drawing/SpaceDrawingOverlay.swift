//
//  SpaceDrawingOverlay.swift
//  Movie Theater Experience
//
//  Created by GPT-5 Codex on 3/16/25.
//

import SwiftUI

struct SpaceDrawingCanvasView: View {
    @ObservedObject var viewModel: SpaceDrawingViewModel
    
    private var aspectRatio: CGFloat {
        CGFloat(SpaceDrawingConstants.planeSizeMeters.x / SpaceDrawingConstants.planeSizeMeters.y)
    }
    
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewModel.processDragChanged(at: value.location, in: geometry.size)
                        }
                        .onEnded { _ in
                            viewModel.processDragEnded()
                        }
                )
                .overlay(overlayGuide)
                .opacity(viewModel.isOverlayVisible ? 1 : 0)
                .allowsHitTesting(viewModel.isOverlayVisible)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }
    
    private var overlayGuide: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.35),
                        .white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("3D Sketch Volume")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.8))
                    Text("10 m cube fixed at the starting position—hand/controller depth carves the path.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(14)
            }
            .overlay(alignment: .bottomTrailing) {
                Label(viewModel.selectedTool == .brush ? "Brush" : "Eraser",
                      systemImage: viewModel.selectedTool == .brush ? "paintbrush.pointed" : "eraser")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(14)
            }
            .padding(8)
    }
}
