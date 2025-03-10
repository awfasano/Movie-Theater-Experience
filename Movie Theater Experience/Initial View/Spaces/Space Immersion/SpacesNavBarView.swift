//
//  SpacesNavBarView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/2/25.
//
import Foundation
import SwiftUI

struct SpacesNavBarView: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    // Local state for toggling hide/show immersive view.
    @State private var isContentHidden: Bool = false

    var body: some View {
        HStack(spacing: 20) {
            // Exit immersive view
            Button(action: {
                Task {
                    await dismissImmersiveSpace()
                }
            }) {
                Label("Exit", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            
            // Hide immersive view (for example, collapse/hide some overlay)
            Button(action: {
                withAnimation {
                    isContentHidden.toggle()
                }
            }) {
                Label(isContentHidden ? "Show" : "Hide", systemImage: isContentHidden ? "eye.fill" : "eye.slash.fill")
            }
            .buttonStyle(.bordered)
            
            // Open Emoji Buttons Window
            Button(action: {
                openWindow(id: "emojiWindow")
            }) {
                Label("Emoji", systemImage: "face.smiling")
            }
            .buttonStyle(.bordered)
            
            // Open Chat Messages Window
            Button(action: {
                openWindow(id: "chatWindow")
            }) {
                Label("Chat", systemImage: "message.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(radius: 5)
        .opacity(isContentHidden ? 0.0 : 1.0)
    }
}
