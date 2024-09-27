import SwiftUI

struct EmojiButtonView: View {
    func buttonTapped(emoji: String) {
        print("\(emoji) button tapped")
        // Add additional actions here based on the tapped emoji
    }

    var body: some View {
        HStack(spacing: 20) {
            ForEach(["❤️", "😢", "😍", "😂", "💬"], id: \.self) { emoji in
                Button(action: { buttonTapped(emoji: emoji) }) {
                    Text(emoji)
                        .font(.extraLargeTitle2)
                        .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(.lift)
                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 2)
            }
        }
        .padding()
        .background(Color.clear)
    }
}
