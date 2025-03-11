import SwiftUI

struct ChatScrollView: View {
    let messages: [ChatMessage]
    let viewModel: ChatViewModel
    @StateObject private var positionTracker = MessagePositionTracker()
    @State private var scrollOffset: CGFloat = 0
    @State private var viewHeight: CGFloat = 0
    @State private var messageOpacities: [String: Double] = [:]
    @State private var shouldScrollToBottom = false
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    messagesList(proxy: proxy)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .named("scroll")).minY
                                )
                            }
                        )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    scrollOffset = offset
                    viewHeight = geometry.size.height
                    Task {
                        await updateOpacities()
                    }
                }
                .onChange(of: messages.count) { newCount in
                    shouldScrollToBottom = true
                }
                .onChange(of: shouldScrollToBottom) { newValue in
                    if newValue {
                        scrollToLatest(proxy)
                        shouldScrollToBottom = false
                    }
                }
            }
        }
    }
    
    private func messagesList(proxy: ScrollViewProxy) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                messageRow(index: index, message: message)
                    .id(message.id)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: MessagePositionPreferenceKey.self,
                                    value: [MessagePosition(id: message.id, position: geo.frame(in: .named("scroll")).minY)]
                                )
                        }
                    )
            }
        }
        .padding(.vertical)
        .onPreferenceChange(MessagePositionPreferenceKey.self) { positions in
            for position in positions {
                positionTracker.updateFrame(
                    CGRect(x: 0, y: position.position, width: 0, height: 0),
                    for: position.id
                )
            }
            Task {
                await updateOpacities()
            }
        }
    }
    
    private func messageRow(index: Int, message: ChatMessage) -> some View {
        let isFirst = index == 0 || messages[index - 1].senderId != message.senderId
        
        return MessageRow(
            message: message,
            isFirstInSequence: isFirst,
            showTimestamp: index % 3 == 0,
            opacity: messageOpacities[message.id] ?? 1.0
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: messages.count)
    }
    
    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let lastId = messages.last?.id else { return }
        
        withAnimation {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
        
        // Add a slight delay and scroll again to ensure it reaches the bottom
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
    
    private func updateOpacities() async {
        for message in messages {
            let opacity = calculateOpacity(for: message.id)
            await viewModel.updateMessageOpacity(id: message.id, opacity: opacity)
            messageOpacities[message.id] = opacity
        }
    }
    
    private func calculateOpacity(for messageId: String) -> Double {
        let topFadeThreshold: CGFloat = 150
        let bottomFadeThreshold: CGFloat = viewHeight - 200
        
        guard let messageFrame = positionTracker.getFrame(for: messageId) else { return 1.0 }
        
        // Top fade
        if messageFrame.minY < topFadeThreshold {
            return max(0.1, messageFrame.maxY / topFadeThreshold)
        }
        
        return 1.0
    }
}
