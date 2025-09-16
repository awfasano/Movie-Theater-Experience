//
//  TriviaEmojiReactions.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import SwiftUI

struct TriviaEmojiReactions: View {
    let tableNumber: Int
    @EnvironmentObject private var spacesEntityWrapper: SpacesEntityWrapper

    var body: some View {
        HStack(spacing: 12) {
            EmojiTriggerButton(emoji: "thinking", systemImage: "brain.head.profile")
            EmojiTriggerButton(emoji: "lightbulb", systemImage: "lightbulb.fill")
            EmojiTriggerButton(emoji: "celebration", systemImage: "party.popper.fill")
            EmojiTriggerButton(emoji: "confident", systemImage: "hand.thumbsup.fill")
            EmojiTriggerButton(emoji: "uncertain", systemImage: "questionmark.circle.fill")
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func EmojiTriggerButton(emoji: String, systemImage: String) -> some View {
        Button {
            triggerTableEmoji(emoji)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .padding(8)
                .background(.thinMaterial)
                .clipShape(Circle())
        }
    }

    private func triggerTableEmoji(_ emojiName: String) {
        spacesEntityWrapper.updateVolumetricEmojiTexture(with: emojiName, isLooping: false)
        // Optionally broadcast emoji to table/team
    }
}
