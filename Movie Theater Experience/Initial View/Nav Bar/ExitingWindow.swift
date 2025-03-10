import SwiftUI

struct ExitingWindow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    let stats: WatchStats
    
    // Animation states
    @State private var showContent = false
    @State private var showStars = false
    @State private var showStats = false
    
    var body: some View {
        ZStack {
            // Background
            background
            
            // Main Content
            VStack(spacing: 20) {
                // Header
                Text("Thanks for Watching!")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                
                // Decorative Line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 200, height: 2)
                    .padding(.vertical, 20)
                    .opacity(showContent ? 1 : 0)
                
                // Main Message
                Text("We hope you enjoyed the show!\nCome back soon for more amazing experiences.")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 20)
                    .opacity(showContent ? 1 : 0)
                
                // Stats Section
                HStack(spacing: 40) {
                    StatCard(
                        title: "Watch Time",
                        value: formatWatchTime(stats.watchTime),
                        icon: "clock.fill"
                    )
                    
                    StatCard(
                        title: "Viewers",
                        value: "\(stats.viewerCount)",
                        icon: "person.2.fill"
                    )
                }
                .opacity(showStats ? 1 : 0)
                .offset(y: showStats ? 0 : 30)
                
                Spacer(minLength: 20)
                
                // Footer text
                Text("Your next movie adventure awaits!")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(showContent ? 1 : 0)
                
                Spacer(minLength: 20)
                
                // Close Button
                Button(action: handleReturn) {
                    Text("Close")
                        .font(.headline)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                }
                .opacity(showContent ? 1 : 0)
            }
            .padding(60)
        }
        .mask(RoundedRectangle(cornerRadius: 40))
        .onAppear {
            withAnimation(.easeOut(duration: 1)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 2)) {
                showStars = true
            }
            withAnimation(.spring(duration: 1, bounce: 0.3).delay(0.3)) {
                showStats = true
            }
        }
    }
    
    private var background: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.8)
            
            // Decorative stars
            ForEach(0..<20) { index in
                Circle()
                    .fill(.white)
                    .frame(width: 3, height: 3)
                    .position(
                        x: CGFloat.random(in: 0...400),
                        y: CGFloat.random(in: 0...600)
                    )
                    .opacity(showStars ? 0.5 : 0)
                    .animation(
                        .easeInOut(duration: 1).delay(Double(index) * 0.1),
                        value: showStars
                    )
            }
        }
    }
    
    private func handleReturn() {
        // Dismiss all windows
        dismissAllWindows()
        
        // Small delay to ensure clean transitions
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            // Show the schedule
            openWindow(id: WindowType.tabBar.rawValue)
        }
    }
    
    private func dismissAllWindows() {
        let windowIds = ["chatWindow", "emojiWindow", "movieWindow", "seatMap", "navBar", "exitingWindow"]
        for windowId in windowIds {
            dismissWindow(id: windowId)
        }
    }
    
    private func formatWatchTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.9))
            
            Text(value)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 160, height: 160)
        .background(.ultraThinMaterial.opacity(0.75))
        .cornerRadius(30)
    }
}
