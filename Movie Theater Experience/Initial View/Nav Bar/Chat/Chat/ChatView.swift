import SwiftUI
import FirebaseFirestore

// MessageView Component
struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var textFieldHeight: CGFloat = 40
    @State private var messageOpacities: [String: Double] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ChatScrollView(messages: viewModel.messages, viewModel: viewModel)
                .padding(.bottom, 8)
            
            // Input area
            inputArea
        }
        .task {
            // Update opacities periodically
            while !Task.isCancelled {
                for message in viewModel.messages {
                    let opacity = await viewModel.getOpacity(for: message.id)
                    messageOpacities[message.id] = opacity
                }
                try? await Task.sleep(for: .milliseconds(16)) // ~60fps
            }
        }
    }
    
    private var inputArea: some View {
        VStack {
            Divider()
            
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 12) {
                    // Text input
                    CustomTextInputView(
                        text: $messageText,
                        placeholder: "",
                        onCommit: sendMessage,
                        dynamicHeight: $textFieldHeight,
                        containerWidth: geometry.size.width - 80 // Account for send button and padding
                    )
                    .frame(height: textFieldHeight)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Send button
                    sendButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(height: textFieldHeight + 24) // Account for padding
        }
        .background(.ultraThinMaterial)
    }
    
    private var sendButton: some View {
        Button(action: sendMessage) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(
                    messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .gray
                    : .blue
                )
                .frame(width: 44, height: 44)
        }
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .buttonStyle(.plain)
        .glassBackgroundEffect()
    }
    
    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        viewModel.sendMessage(text: trimmed)
        messageText = ""
        textFieldHeight = 40 // Reset height after sending
    }
}
