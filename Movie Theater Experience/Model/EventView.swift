import SwiftUI
import RealityKit
import RealityKitContent

struct EventView: View {
    // MARK: - Properties
    var event: CalendarEvent
    @State private var isEventAccessible = false
    @State private var accessMessage = ""
    @State private var countdownText: String = ""
    @State private var isPressing = false
    @State private var isHovered = false
    
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismiss) private var dismiss
    
    private let spaceManager = ImmersiveSpaceManager.shared
    
    // MARK: - Constants
    private let baseDepth: Double = 15
    private let hoverDepth: Double = 50
    private let pressDepth: Double = 0
    private let baseShadowRadius: Double = 20
    private let hoverShadowRadius: Double = 30
    private let baseShadowY: Double = 10
    private let hoverShadowY: Double = 16

    // MARK: - Body
    var body: some View {
        ZStack {
            // Spatial Background with Material
            RoundedRectangle(cornerRadius: 24)
                .fill(.thinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(event.eventColor.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.3), lineWidth: 0.5)
                )
            
            // Content Layer
            VStack(alignment: .leading, spacing: 12) {
                // Title Row
                HStack {
                    Text(event.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    if isEventAccessible {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.primary)
                            .symbolEffect(.bounce, options: .repeating, value: isHovered)
                    }
                }
                
                // Time Display
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, options: .repeating, value: !countdownText.isEmpty)
                    
                    Text("\(formatTime(event.date)) - \(formatTime(event.end))")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                
                // Description
                Text(event.description)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                // Status Messages
                if !isEventAccessible {
                    VStack(alignment: .leading, spacing: 6) {
                        if !accessMessage.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.red)
                                Text(accessMessage)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        if !countdownText.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                    .foregroundStyle(.orange)
                                Text(countdownText)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        // Spatial Interactions
        .offset(z: calculateDepth())
        .opacity(calculateOpacity())
        // Enhanced shadow system
        .shadow(
            color: .black.opacity(0.35),
            radius: calculatePrimaryShadowRadius(),
            x: 0,
            y: calculatePrimaryShadowY()
        )
        .shadow(
            color: .black.opacity(0.25),
            radius: calculateSecondaryShadowRadius(),
            x: 0,
            y: calculateSecondaryShadowY()
        )
        .shadow(
            color: event.eventColor.opacity(0.4),
            radius: calculateColoredShadowRadius(),
            x: 0,
            y: calculateColoredShadowY()
        )
        .hoverEffect(.highlight)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onTapGesture {
            if isEventAccessible {
                withAnimation(.smooth(duration: 0.2)) {
                    isPressing = true
                }
                
                // Reset pressing state and handle selection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.smooth(duration: 0.2)) {
                        isPressing = false
                    }
                    Task {
                        await handleEventSelection()
                    }
                }
            }
        }
        .onAppear {
            updateEventAccessibility()
            updateCountdownTimer()
        }
        .onChange(of: Date.now) { _ in
            updateEventAccessibility()
        }
    }
    // MARK: - Helper Methods
    private func calculateDepth() -> Double {
        if isPressing {
            return pressDepth
        } else if isHovered {
            return hoverDepth
        } else {
            return baseDepth
        }
    }
    
    private func calculateOpacity() -> Double {
        if isHovered {
            return 1.0
        }
        return 0.95
    }
    
    private func calculateShadowRadius() -> Double {
        if isHovered {
            return 12
        }
        return 8
    }
    
    private func updateEventAccessibility() {
        let now = Date()
        isEventAccessible = now >= event.date && now <= event.end
        accessMessage = isEventAccessible ? "" : (now < event.date ? "Event hasn't started yet" : "Event has ended")
    }
    
    private func updateCountdownTimer() {
        let now = Date()
        if now < event.date {
            let minutesLeft = Int(event.date.timeIntervalSince(now) / 60)
            countdownText = "Starts in \(minutesLeft) min"
        } else {
            countdownText = ""
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private func handleEventSelection() async {
        guard isEventAccessible, case .closed = spaceManager.state else {
            print("❌ Space must be closed and event must be accessible")
            return
        }
        
        // Set up data in AppModel
        appModel.selectedVideoURL = event.videoURLObject
        appModel.currentEvent = event
        
        // Clean up any leftover data
        await TheatreEntityWrapper.shared.cleanup()
        SharedSeatSelection.shared.selectedSeatEntity = nil
        
        // Prepare and open the space
        guard await spaceManager.prepareForOpening() else {
            print("❌ Failed to prepare space for opening")
            resetAppState()
            return
        }
        
        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            print("✅ Immersive space opened successfully")
            spaceManager.handleOpenSuccess()
            dismiss()
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            print("❌ Failed to open space")
            spaceManager.handleOpenFailure()
            resetAppState()
        }
    }
    
    private func calculatePrimaryShadowRadius() -> Double {
        let baseRadius = baseShadowRadius
        let hoverRadius = hoverShadowRadius
        let progress = isHovered ? 1.0 : 0.0
        return baseRadius + (hoverRadius - baseRadius) * progress
    }
    
    private func calculatePrimaryShadowY() -> Double {
        let baseY = baseShadowY
        let hoverY = hoverShadowY
        let progress = isHovered ? 1.0 : 0.0
        return baseY + (hoverY - baseY) * progress
    }
    
    private func calculateSecondaryShadowRadius() -> Double {
        return calculatePrimaryShadowRadius() * 0.6
    }
    
    private func calculateSecondaryShadowY() -> Double {
        return calculatePrimaryShadowY() * 0.5
    }
    
    private func calculateColoredShadowRadius() -> Double {
        let baseRadius = baseShadowRadius * 1.5
        let hoverRadius = hoverShadowRadius * 1.5
        let progress = isHovered ? 1.0 : 0.0
        return baseRadius + (hoverRadius - baseRadius) * progress
    }
    
    private func calculateColoredShadowY() -> Double {
        return calculatePrimaryShadowY() * 0.7
    }
    
    
    
    private func resetAppState() {
        appModel.selectedVideoURL = nil
        appModel.currentEvent = nil
    }
}
// MARK: - Custom Hover Effect Gesture
struct HoverEffect: Gesture {
    @Binding var distance: Double
    
    var body: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let maxDistance: Double = 100
                let magnitude = sqrt(
                    pow(value.translation.width, 2) +
                    pow(value.translation.height, 2)
                )
                distance = min(magnitude, maxDistance)
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.3)) {
                    distance = 0
                }
            }
    }
}
