import SwiftUICore

struct ChatBubble: View {
    let message: ChatMessage
    let isIncoming: Bool
    let showTimestamp: Bool
    let isFirstInSequence: Bool
    @ObservedObject private var sharedListener = SharedFirebaseListener.shared  // Add this line
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack {
            
            HStack(alignment: .bottom, spacing: 10) {
                if isIncoming {
                    senderInitialView()
                }
                
                VStack(alignment: isIncoming ? .leading : .trailing, spacing: 5) {
                    Text(message.content)
                        .padding(10)
                        .background(isIncoming ? Color.blue : Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true) // Allow vertical growth
                    
                    if showTimestamp {
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, showTimestamp ? 0 : 6)
                
                if !isIncoming {
                    senderInitialView()
                }
            }
            .opacity(sharedListener.messageOpacities[message.id] ?? 1.0)  // Use direct dictionary access
            .frame(maxWidth: .infinity, alignment: isIncoming ? .leading : .trailing)
            .padding(.horizontal)
            .padding(.vertical, 4) // Add vertical spacing between bubbles
        }
    }
    
    @ViewBuilder
    private func senderInitialView() -> some View {
        Text(message.senderName.prefix(1))
            .frame(width: 30, height: 30)
            .background(isIncoming ? Color.blue.opacity(0.4) : Color.green.opacity(0.4))
            .clipShape(Circle())
            .overlay(Circle().stroke(isIncoming ? Color.blue : Color.green, lineWidth: 2))
            .foregroundColor(.white)
            .font(.caption)
            .padding(.leading, isIncoming ? 4 : 0)
            .padding(.trailing, isIncoming ? 0 : 4)
    }
}
