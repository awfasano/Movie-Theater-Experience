import SwiftUI
import FirebaseFirestore

struct EmojiButtonView: View {
    let dateString: String
    let eventId: String
    
    // Removed sharedListener property since we don't need to start/stop it here
    private let emitterService = EmitterService()
    
    init(eventId: String, date: Date) {
        self.eventId = eventId
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        self.dateString = formatter.string(from: date)
        // Removed listener initialization since it's handled by AppModel
    }
    
    func buttonTapped(emoji: String) {
        print("\(emoji) button tapped")
        
        // Convert emoji to number and corresponding asset name
        let (emojiNumber, assetName): (Int, String)
        switch emoji {
        case "❤️":
            emojiNumber = 0
            assetName = "heart"
        case "😢":
            emojiNumber = 1
            assetName = "crying"
        case "😍":
            emojiNumber = 2
            assetName = "heart eyes"
        case "😂":
            emojiNumber = 3
            assetName = "laughter"
        case "😮":
            emojiNumber = 4
            assetName = "oh"
        default:
            emojiNumber = 0
            assetName = "heart"
        }
        
        // Update the visual emitter first for immediate feedback
        TheatreEntityWrapper.shared.updateVolumetricEmojiTexture(with: assetName)
        
        // Then send to Firebase
        emitterService.sendEmitter(
            dateString: dateString,
            eventId: eventId,
            emoji: emojiNumber,
            seatOrTheatre: false  // false for theatre
        )
    }

    var body: some View {
        HStack(spacing: 20) {
            ForEach(["❤️", "😢", "😍", "😂", "😮"], id: \.self) { emoji in
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
