//
//  AudioWaveformView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 6/21/25.
//

import Foundation
import SwiftUI

/// A view that renders a stylized, scrolling audio waveform.
struct AudioWaveformView: View {
    let audioLevels: [Float]

    var body: some View {
        GeometryReader { geo in                // ← NEW
            let maxH = geo.size.height * 0.85  // 85 % of container

            HStack(spacing: 2) {
                ForEach(audioLevels.indices, id: \.self) { i in
                    let h = max(2, CGFloat(audioLevels[i]) * maxH * 2.2)   // 60 % taller
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barGradient)
                        .frame(height: h)
                        .animation(.linear(duration: 0.05), value: h)
                }
            }
        }
    }

    private var barGradient: LinearGradient {
        LinearGradient(gradient: .init(colors: [Color.purple, Color.purple.opacity(0.7)]),
                       startPoint: .top, endPoint: .bottom)
    }
}


/// A single bar in the waveform, including its glow and reflection.
private struct WaveformBar: View {
    let level: CGFloat
    
    // Define the gradient once to reuse it.
    private var barGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color.purple, Color.purple.opacity(0.7)]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    var body: some View {
        // UPDATED: Simplified the bar. The "ghost" effect was removed in favor of the scrolling effect.
        let barHeight = max(2, level * 200)   // was 50 / 60 – now ~90 pts max

        RoundedRectangle(cornerRadius: 3)
            .fill(barGradient)
            .frame(height: barHeight)
            // Animate height changes smoothly.
            .animation(.linear(duration: 0.05), value: level)
    }
}
