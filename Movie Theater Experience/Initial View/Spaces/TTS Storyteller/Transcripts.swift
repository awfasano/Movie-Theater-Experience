//
//  TranscriptView.swift
//  Movie Theater Experience
//
//  A scrollable view showing conversation transcripts
//

import SwiftUI

struct TranscriptView: View {
    let transcripts: [LiveStorytellerService.TranscriptEntry]
    @Namespace private var bottomID
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if transcripts.isEmpty {
                        Text("Start talking to see transcripts...")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(transcripts) { entry in
                            TranscriptBubble(entry: entry)
                                .id(entry.id)
                        }
                    }
                    
                    // Invisible anchor for auto-scrolling
                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .padding()
            }
            .onChange(of: transcripts.count) { _ in
                withAnimation {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
    }
}

struct TranscriptBubble: View {
    let entry: LiveStorytellerService.TranscriptEntry
    
    private var isUser: Bool {
        entry.role == "user"
    }
    
    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Role label
                Text(isUser ? "You" : "Storyteller")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Message bubble
                HStack {
                    Text(entry.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    
                    // Show typing indicator for partial messages
                    if !entry.isFinal {
                        HStack(spacing: 2) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(isUser ? Color.white.opacity(0.7) : Color.primary.opacity(0.4))
                                    .frame(width: 4, height: 4)
                                    .scaleEffect(1.0)
                                    .animation(
                                        Animation.easeInOut(duration: 0.5)
                                            .repeatForever()
                                            .delay(Double(index) * 0.1),
                                        value: UUID()
                                    )
                            }
                        }
                        .padding(.trailing, 8)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isUser ? Color.purple : Color(.secondarySystemBackground))
                        .opacity(entry.isFinal ? 1.0 : 0.8)
                )
                .foregroundColor(isUser ? .white : .primary)
            }
            
            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }
}
