//
//  Untitled.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 5/5/25.
//

import SwiftUI

struct EndScreen: View {
    var onExit: () -> Void

    var body: some View {
        ZStack {
            // Confetti behind content
            ConfettiView()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("🎬  Thank you for watching!")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Button("Exit") { onExit() }
                    .buttonStyle(.borderedProminent)
                    .font(.title2)
            }
            .padding(60)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 32))
            .shadow(radius: 20)
        }
        .transition(.opacity.combined(with: .scale))
    }
}

