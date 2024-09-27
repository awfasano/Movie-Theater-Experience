import SwiftUI
import FirebaseFirestore

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var textFieldHeight: CGFloat = 40
    @State private var visibleMessageIds: Set<String> = []
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .edgesIgnoringSafeArea(.all)

            VStack {
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) { // Added .vertical
                            LazyVStack(spacing: 10) {
                                ForEach(viewModel.messages.indices, id: \.self) { index in
                                    let message = viewModel.messages[index]
                                    ChatBubble(
                                        message: message,
                                        isIncoming: message.senderId != "currentUserId",
                                        showTimestamp: (index % 3 == 0), // Show timestamp for every third message
                                        // Alternatively, if you want to start showing the timestamp from the first message and then every third message after:
                                        // showTimestamp: ((index + 1) % 3 == 0) // Adjust based on your indexing preference
                                        viewModel: viewModel
                                    )
                                    .id(message.id)
                                    .onAppear {
                                        visibleMessageIds.insert(message.id)
                                    }
                                    .onDisappear {
                                        visibleMessageIds.remove(message.id)
                                    }
                                }
                            }
                            .padding(.top)
                        }
                        .coordinateSpace(name: "scroll") // Add coordinate space
                        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                            scrollOffset = value // Track scroll offset
                        }
                        .onChange(of: viewModel.messages.count) {
                            if let lastMessageId = viewModel.messages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastMessageId, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                // Message Input Area
                HStack(alignment: .center) {
                    ExpandingTextField(text: $messageText, placeholder: "message", onCommit: {
                        sendMessage()
                    }, dynamicHeight: $textFieldHeight)
                        .frame(height: textFieldHeight)
                        .padding(.horizontal)
                    Button(action: sendMessage) {
                        Text("Send")
                            .fontWeight(.semibold)
                            .foregroundColor(.white) // Change text color as needed
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .clipShape(Capsule()) // Gives it a rounded pill shape
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.bottom)
            }
            .padding(.all, 5)
        }
        .navigationBarTitle("Chat", displayMode: .inline)
    }

    private func sendMessage() {
        viewModel.sendMessage(text: messageText.trimmingCharacters(in: .whitespacesAndNewlines))
        messageText = ""
    }
}
