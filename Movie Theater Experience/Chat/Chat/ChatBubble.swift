import SwiftUICore
import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    let showTimestamp: Bool
    let isFirstInSequence: Bool
    let opacity: Double
    
    // Retrieve the current user’s name.
    @AppStorage("username") private var currentUserName: String = "User"
    // Retrieve the current user's unique identifier.
    @AppStorage("userId") private var currentUserId: String = ""
    
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
        if message.senderId == currentUserId {
            return currentUserName
        } else {
            return message.senderName
        }
    }
    
    // Compute isIncoming based on whether the senderId matches the current user's id.
    private var isIncoming: Bool {
        return message.senderId != currentUserId
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
        // Determine which name to use: for current user use currentUserName, otherwise message.senderName.
        let name = message.senderId == currentUserId ? currentUserName : message.senderName
        let initial = name.prefix(1).uppercased()
        
        return Text(initial)
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 40, height: 40)
            .background(message.senderId == currentUserId ? sentMessageColor : receivedMessageColor)
            .clipShape(Circle())
    }
}
