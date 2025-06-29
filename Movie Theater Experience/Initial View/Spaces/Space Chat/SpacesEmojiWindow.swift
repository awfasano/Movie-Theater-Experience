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
    
    var body: some View {
        VStack {
            // Window Header
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
            
            Divider()
            
            HStack(spacing: 20) {
                ForEach(viewModel.emojiTypes, id: \.unicode) { emojiType in
                    Button(action: {
                        Task {
                            await viewModel.processEmojiTap(emoji: emojiType.unicode)
                        }
                    }) {
                        Text(emojiType.unicode)
                            .font(.system(size: 36))
                            .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 2)
                            .opacity(viewModel.isOnCooldown ? 0.5 : 1.0)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(.lift)
                    .disabled(viewModel.isOnCooldown)
                }
            }
            .padding(.vertical, 20)
            
            if viewModel.isOnCooldown {
                Text("Please wait...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            // Set the current space ID when the window appears
            if let spaceId = currentSpaceId {
                viewModel.setSpaceId(spaceId)
            }
        }
    }
    
    // Get the current space ID from either source
    private var currentSpaceId: String? {
        return appModel.selectedSpace?.id ?? selectedSpace.space?.id
    }
}

