//
//  SpacesEmojiWindow.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/10/25.
//

import Foundation
import SwiftUI

struct SpacesEmojiWindow: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var selectedSpace: SelectedSpace
    @StateObject private var viewModel = SpacesEmojiViewModel()
    @Environment(\.dismissWindow) private var dismissWindow
    
    // Animation states
    @State private var windowScale: CGFloat = 0.95
    @State private var windowOpacity: Double = 0
    @State private var emojiScales: [String: CGFloat] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Emoji buttons
            emojiButtonsView
                .padding(.vertical, 20)
            
            // Cooldown indicator
            cooldownIndicator
                .frame(height: 20)
                .padding(.bottom, 10)
        }
        .padding(.horizontal)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(windowScale)
        .opacity(windowOpacity)
        .task {
            await initializeWindow()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Spacer()
            Text("Emoji Reactions")
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
    }
    
    private var emojiButtonsView: some View {
        HStack(spacing: 16) {
            ForEach(viewModel.emojiTypes) { emojiType in
                EmojiButton(
                    emojiType: emojiType,
                    isOnCooldown: viewModel.isOnCooldown,
                    isActive: viewModel.activeEmoji == emojiType.unicode,
                    scale: emojiScales[emojiType.unicode] ?? 1.0,
                    action: {
                        handleEmojiTap(emojiType.unicode)
                    }
                )
            }
        }
        .padding(.horizontal, 10)
    }
    
    private var cooldownIndicator: some View {
        Group {
            if viewModel.isOnCooldown && !viewModel.isEmitting {
                VStack(spacing: 4) {
                    // Progress bar
                    ProgressView()
                        .progressViewStyle(.linear)
                    
                    Text("Cooldown...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isOnCooldown)
    }
    
    // MARK: - Helper Methods
    
    private var currentSpaceId: String? {
        return appModel.selectedSpace?.id ?? selectedSpace.space?.id
    }
    
    @MainActor
    private func initializeWindow() async {
        // Initialize emoji scales
        for emojiType in viewModel.emojiTypes {
            emojiScales[emojiType.unicode] = 1.0
        }
        
        // Set the space ID
        if let spaceId = currentSpaceId {
            viewModel.setSpaceId(spaceId)
        }
        
        // Animate window appearance
        try? await Task.sleep(for: .milliseconds(50))
        
        withAnimation(.easeOut(duration: 0.3)) {
            windowScale = 1.0
            windowOpacity = 1.0
        }
    }
    
    private func handleEmojiTap(_ emoji: String) {
        // Animate the tapped emoji
        withAnimation(.easeInOut(duration: 0.1)) {
            emojiScales[emoji] = 0.85
        }
        
        // Bounce back animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.1)) {
            emojiScales[emoji] = 1.0
        }
        
        // Process the emoji
        viewModel.processEmojiTap(emoji: emoji)
    }
}

// MARK: - EmojiButton Component

struct EmojiButton: View {
    let emojiType: SpacesEmojiViewModel.EmojiType
    let isOnCooldown: Bool
    let isActive: Bool
    let scale: CGFloat
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text(emojiType.unicode)
                .font(.system(size: 36))
                .scaleEffect(scale)
                .opacity(opacity)
                .shadow(
                    color: shadowColor,
                    radius: isActive ? 4 : 2,
                    x: 0,
                    y: 2
                )
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.1 : 0))
                        .scaleEffect(1.3)
                        .blur(radius: 8)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isOnCooldown)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering && !isOnCooldown
            }
        }
    }
    
    private var opacity: Double {
        if isActive {
            return 1.0
        } else if isOnCooldown {
            return 0.4
        } else {
            return 1.0
        }
    }
    
    private var shadowColor: Color {
        if isActive {
            return Color.blue.opacity(0.6)
        } else {
            return Color.black.opacity(0.3)
        }
    }
}