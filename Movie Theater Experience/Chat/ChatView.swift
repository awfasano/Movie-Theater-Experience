import SwiftUI
import FirebaseFirestore


import SwiftUI
import FirebaseFirestore

struct ChatView: View {
    // MARK: - Properties
    @StateObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var textFieldHeight: CGFloat = 40
    @State private var visibleMessageIds: Set<String> = []
    @State private var scrollOffset: CGFloat = 0
    @State private var windowHeight: CGFloat = 0
    
    var body: some View {
        GeometryReader { mainGeometry in
            ZStack {
                Color(.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            GeometryReader { geometry in
                                Color.clear.preference(key: ScrollOffsetPreferenceKey.self,
                                                    value: geometry.frame(in: .named("scroll")).origin.y)
                            }
                            .frame(height: 0)
                            
                            LazyVStack(spacing: 0) {
                                ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                                    let isFirstInSequence = index == 0 || viewModel.messages[index - 1].senderId != message.senderId
                                    
                                    ChatBubble(
                                        message: message,
                                        isIncoming: message.senderId != "currentUserId",
                                        showTimestamp: index % 3 == 0,
                                        isFirstInSequence: isFirstInSequence,
                                        viewModel: viewModel
                                    )
                                    .id(message.id)
                                    .background(
                                        GeometryReader { geometry in
                                            Color.clear.preference(
                                                key: MessagePositionPreferenceKey.self,
                                                value: [MessagePosition(id: message.id,
                                                                      position: geometry.frame(in: .named("scroll")).minY)]
                                            )
                                        }
                                    )
                                }
                            }
                            .padding(.top)
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(MessagePositionPreferenceKey.self) { positions in
                            for position in positions {
                                let opacity = calculateOpacity(position: position.position,
                                                            windowHeight: mainGeometry.size.height)
                                viewModel.updateMessageOpacity(id: position.id, opacity: opacity)
                            }
                        }
                        .onChange(of: viewModel.messages.count) { _ in
                            if let lastMessageId = viewModel.messages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastMessageId, anchor: .bottom)
                                }
                            }
                        }
                        .onAppear {
                            if let lastMessageId = viewModel.messages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastMessageId, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Message Input Area
                    HStack(alignment: .center) {
                        ExpandingTextField(text: $messageText,
                                         placeholder: "message",
                                         onCommit: { sendMessage() },
                                         dynamicHeight: $textFieldHeight)
                            .frame(height: textFieldHeight)
                            .padding(.horizontal)
                        
                        Button(action: sendMessage) {
                            Text("Send")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                                .clipShape(Capsule())
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.bottom)
                }
                .padding(.all, 5)
            }
        }
        .navigationBarTitle("Chat", displayMode: .inline)
    }
    
    // MARK: - Methods
    private func sendMessage() {
        viewModel.sendMessage(text: messageText.trimmingCharacters(in: .whitespacesAndNewlines))
        messageText = ""
    }
    
    private func calculateOpacity(position: CGFloat, windowHeight: CGFloat) -> Double {
        let normalizedPosition = position / windowHeight
        
        // Make the fade zones more aggressive
        let topFadeZone = -0.5  // Brought closer to 0 from -0.5
        let fadeEndZone = 0.5   // Increased from 0.5 to spread the fade
        
        // Determine minimum opacity based on window height
        let minOpacity = windowHeight > 650 ? 0.0 : 0.2
        
        if normalizedPosition <= topFadeZone {
            return minOpacity
        } else if normalizedPosition >= fadeEndZone {
            return 1.0
        } else {
            let fadeProgress = (normalizedPosition - topFadeZone) / (fadeEndZone - topFadeZone)
            // Much more aggressive power curve
            let fadeAmount = pow(max(0, min(1, fadeProgress)), 6.0)
            return minOpacity + (fadeAmount * (1.0 - minOpacity))
        }
    }
}

struct MessagePosition: Equatable {
    let id: String
    let position: CGFloat
}

struct MessagePositionPreferenceKey: PreferenceKey {
    static var defaultValue: [MessagePosition] = []
    
    static func reduce(value: inout [MessagePosition], nextValue: () -> [MessagePosition]) {
        value.append(contentsOf: nextValue())
    }
}

struct BubbleSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// Separate container for geometry reading
struct ChatBubbleContainer: View {
    // MARK: - Properties
    let message: ChatMessage
    let isIncoming: Bool
    let showTimestamp: Bool
    let isFirstInSequence: Bool
    @ObservedObject var viewModel: ChatViewModel
    let windowHeight: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ChatBubble(
                message: message,
                isIncoming: isIncoming,
                showTimestamp: showTimestamp,
                isFirstInSequence: isFirstInSequence,
                viewModel: viewModel
            )
            .frame(maxWidth: .infinity)
            .onChange(of: geometry.frame(in: .named("scroll")).minY) { position in
                let opacity = calculateOpacity(position: position, windowHeight: windowHeight)
                viewModel.updateMessageOpacity(id: message.id, opacity: opacity)
            }
            .onAppear {
                let position = geometry.frame(in: .named("scroll")).minY
                let opacity = calculateOpacity(position: position, windowHeight: windowHeight)
                viewModel.updateMessageOpacity(id: message.id, opacity: opacity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private func calculateOpacity(position: CGFloat, windowHeight: CGFloat) -> Double {
        let normalizedPosition = position / windowHeight
        
        let topFadeZone = -0.5
        let fadeEndZone = 0.5
        
        let minOpacity = windowHeight > 650 ? 0.0 : 0.2
        
        if normalizedPosition <= topFadeZone {
            return minOpacity
        } else if normalizedPosition >= fadeEndZone {
            return 1.0
        } else {
            let fadeProgress = (normalizedPosition - topFadeZone) / (fadeEndZone - topFadeZone)
            let fadeAmount = pow(max(0, min(1, fadeProgress)), 6.0)
            return minOpacity + (fadeAmount * (1.0 - minOpacity))
        }
    }
}
