import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    let showTimestamp: Bool
    let isFirstInSequence: Bool
    let opacity: Double
    
    @Environment(AppModel.self) private var appModel
    
    // Retrieve the persisted bubble colors.
    @AppStorage("sentMessageColorHex") private var sentMessageColorHex: String = "#0000FF"
    @AppStorage("receivedMessageColorHex") private var receivedMessageColorHex: String = "#808080"
    
    // Convert hex strings to Color.
    private var sentMessageColor: Color {
        Color(hex: sentMessageColorHex) ?? .blue
    }
    
    private var receivedMessageColor: Color {
        Color(hex: receivedMessageColorHex) ?? .gray
    }
    
    // Computed property for display name.
    private var displayName: String {
        // +++ USE AppModel FOR THE CHECK +++
        if message.senderId == appModel.currentUserId {
            return appModel.username // Use the name from the model
        } else {
            return message.senderName
        }
    }
    
    // Compute isIncoming based on whether the senderId matches the current user's id.
    private var isIncoming: Bool {
        return message.senderId != appModel.currentUserId
    }
    
    var body: some View {
        VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                if isIncoming {
                    senderAvatar
                }
                
                VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
                    if isFirstInSequence {
                        Text(displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isIncoming ? receivedMessageColor : sentMessageColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                if !isIncoming {
                    senderAvatar
                }
            }
            
            if showTimestamp {
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .opacity(opacity)
        .frame(maxWidth: .infinity, alignment: isIncoming ? .leading : .trailing)
    }
    
    private var senderAvatar: some View {
        // --- FIX IS HERE ---
        // We now get the user's name and ID from the appModel.
        let name = message.senderId == appModel.currentUserId ? appModel.username : message.senderName
        let initial = name.prefix(1).uppercased()
        
        return Text(initial)
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 40, height: 40)
            // And we use the appModel here as well for the background color check.
            .background(message.senderId == appModel.currentUserId ? sentMessageColor : receivedMessageColor)
            .clipShape(Circle())
    }
}
