import SwiftUI
import FirebaseFirestore

struct EmojiButtonView: View {
    let eventId: String
    let date: Date
    @State private var emojiManager = EmojiManager.shared
    
    var body: some View {
        HStack(spacing: 20) {
            ForEach(emojiManager.emojiTypes, id: \.unicode) { emojiType in
                Button(action: {
                    Task {
                        await emojiManager.processEmojiTap(
                            emoji: emojiType.unicode,
                            eventId: eventId,
                            date: date
                        )
                    }
                }) {
                    Text(emojiType.unicode)
                        .font(.extraLargeTitle2)
                        .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 2)
                        .opacity(emojiManager.isOnCooldown ? 0.5 : 1.0)
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(.lift)
                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 2)
                .disabled(emojiManager.isOnCooldown)
            }
        }
        .padding()
        .background(Color.clear)
    }
}
