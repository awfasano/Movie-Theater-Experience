import SwiftUI

struct ChatBubble: View {
    var message: ChatMessage
    var isIncoming: Bool
    var showTimestamp: Bool
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Conditionally show sender initial for incoming messages
            if isIncoming {
                senderInitialView()
            }
            
            VStack(alignment: isIncoming ? .leading : .trailing, spacing: 5) {
                // Message Text
                Text(message.content)
                    .padding(10)
                    .background(isIncoming ? Color.blue : Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundColor(.white)
                
                // Timestamp
                if showTimestamp {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, showTimestamp ? 0 : 6)
            .background(geometrySensor) // Injected GeometryReader usage

            // Sender initial for outgoing messages
            if !isIncoming {
                senderInitialView()
            }
        }
        .opacity(viewModel.getOpacity(id: message.id))
        .frame(maxWidth: .infinity, alignment: isIncoming ? .leading : .trailing)
        .padding(.horizontal)
    }
    
    // Function to render sender's initial view
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
    
    // GeometryReader used here for detecting the frame
    // without altering the layout of the chat bubble
    private var geometrySensor: some View {
        GeometryReader { geometry in
            Color.clear
                .onChange(of: geometry.frame(in: .global).minY) { newY,OldY in
                    let opacity = calculateOpacity(minY: newY)
                    viewModel.updateMessageOpacity(id: message.id, opacity: opacity)
                    //print(opacity)
                }
        }
        .frame(height: 0) // Keep minimizing impact on layout
    }
    
    private func calculateOpacity(minY: CGFloat) -> Double {
        let threshold: CGFloat = 1400 // Adjust this threshold as needed
        let opacity = Double(minY / threshold)
        return max(min(opacity, 1), 0) // Ensures opacity is between 0 and 1
    }
}


// Preferences
struct YPositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension CoordinateSpace {
    static let scroll = CoordinateSpace.named("scroll")
}

