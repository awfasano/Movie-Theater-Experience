import SwiftUI
import Foundation

struct TrophyView: View {
    var body: some View {
        ZStack {
            // Glow behind the trophy
            Circle()
                .fill(
                    RadialGradient(colors: [Color.yellow.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 120)
                )
                .frame(width: 220, height: 220)
                .blur(radius: 8)
                .opacity(0.9)

            // Trophy symbol with a gold-like gradient
            Image(systemName: "trophy.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .foregroundStyle(
                    LinearGradient(colors: [Color.yellow, Color.orange, Color.yellow.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .orange.opacity(0.4), radius: 12, x: 0, y: 6)
                .overlay {
                    // Specular highlight
                    LinearGradient(colors: [Color.white.opacity(0.6), .clear], startPoint: .top, endPoint: .center)
                        .mask(
                            Image(systemName: "trophy.fill")
                                .resizable()
                                .scaledToFit()
                        )
                }
        }
        .accessibilityLabel(Text("Trophy"))
    }
}

#Preview("TrophyView") {
    ZStack {
        Color.black.opacity(0.9).ignoresSafeArea()
        TrophyView()
            .padding()
            .preferredColorScheme(.dark)
    }
}
