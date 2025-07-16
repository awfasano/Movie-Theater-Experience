//
//  SpacesChatWindow.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/10/25.
//

import Foundation
import SwiftUI

struct SpacesChatWindow: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var selectedSpace: SelectedSpace
    @State private var viewModel: SpacesChatViewModel?
    @Environment(\.dismissWindow) private var dismissWindow
    
    // Animation states
    @State private var isContentVisible = false
    @State private var isInitializing = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Window Header - Isolated from content animations
            // Main content with isolated animation
            ZStack {
                if let viewModel = viewModel {
                    ChatView(viewModel: viewModel)
                        .opacity(isContentVisible ? 1 : 0)
                        .scaleEffect(isContentVisible ? 1 : 0.95)
                        .animation(.easeOut(duration: 0.2), value: isContentVisible)
                        .task {
                            // Delay the animation slightly to prevent stuttering
                            try? await Task.sleep(for: .milliseconds(50))
                            isContentVisible = true
                        }
                } else if isInitializing {
                    loadingView
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped() // Prevent content from overflowing during animations
        }
        .task {
            await initializeViewModel()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Spacer()
            Text("Space Chat")
                .font(.headline)
                .padding(.top, 8)
            Spacer()
            
            Button(action: {
                dismissWindow()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .padding(.horizontal)
        .background(.regularMaterial) // Add background to prevent transparency issues
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
            
            Text("Loading chat...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private var currentSpaceId: String? {
        return appModel.selectedSpace?.id ?? selectedSpace.space?.id
    }
    
    @MainActor
    private func initializeViewModel() async {
        guard viewModel == nil,
              let spaceId = currentSpaceId else {
            isInitializing = false
            return
        }
        
        // Small delay to let the window settle
        try? await Task.sleep(for: .milliseconds(100))
        
        // Initialize view model
        withAnimation(.easeOut(duration: 0.2)) {
            self.viewModel = SpacesChatViewModel(spaceId: spaceId)
            self.isInitializing = false
        }
    }
}
