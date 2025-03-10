import SwiftUICore

struct ChatBubble: View {
    let message: ChatMessage
    let isIncoming: Bool
    let showTimestamp: Bool
    let isFirstInSequence: Bool
    let opacity: Double
    
    var body: some View {
        VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                if isIncoming {
                    senderAvatar
                }
                
                VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
                    if isFirstInSequence {
                        Text(message.senderName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isIncoming ? Color.blue : Color.green)
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
        Text(message.senderName.prefix(1).uppercased())
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(isIncoming ? Color.blue : Color.green)
            .clipShape(Circle())
    }
}
