import SwiftUI

struct EventView: View {
    // MARK: - Properties
    var event: CalendarEvent
    @State private var isEventAccessible = false
    @State private var accessMessage = ""
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismiss) private var dismiss

    
    // MARK: - Computed Properties
    private var textColor: Color {
        switch event.color {
        case 1: return .white  // For red background
        case 2: return .black  // For green background
        case 3: return .white  // For blue background
        case 4: return .white  // For purple background
        case 5: return .black  // For orange background
        case 6: return .black  // For yellow background
        default: return .white
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(event.eventColor.opacity(isEventAccessible ? 1.0 : 0.5))
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(event.title)
                    .font(.headline)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                
                // Time
                HStack {
                    Text(formatTime(event.date))
                        .font(.caption)
                        .foregroundColor(textColor)
                    
                    Text("-")
                        .font(.caption)
                        .foregroundColor(textColor)
                    
                    Text(formatTime(event.end))
                        .font(.caption)
                        .foregroundColor(textColor)
                }
                
                // Description
                Text(event.description)
                    .font(.caption)
                    .foregroundColor(textColor)
                    .lineLimit(2)
                
                // Access status message
                if !isEventAccessible {
                    Text(accessMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            updateEventAccessibility()
        }
        .onChange(of: Date.now) { _ in
            updateEventAccessibility()
        }
        .opacity(isEventAccessible ? 1.0 : 0.7)
        .onTapGesture {
            if isEventAccessible {
                handleEventSelection()
            }
        }
    }
    
    // MARK: - Methods
    private func updateEventAccessibility() {
        let now = Date()
        
        if now < event.date {
            isEventAccessible = false
            accessMessage = "Event hasn't started yet"
        } else if now > event.end {
            isEventAccessible = false
            accessMessage = "Event has ended"
        } else {
            isEventAccessible = true
            accessMessage = ""
        }
    }
    
    private func handleEventSelection() {
        guard isEventAccessible else { return }
        
        appModel.selectedVideoURL = event.videoURLObject
        appModel.currentEvent = event
        
        // First open the immersive space
        Task { @MainActor in
            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                case .opened:
                    appModel.immersiveSpaceState = .open
                    // After immersive space is opened, open the navigation bar and dismiss the current window
                    openWindow(id: "navBar")
                    dismiss() // Dismiss the current window
                case .userCancelled, .error:
                    appModel.immersiveSpaceState = .closed
                @unknown default:
                    appModel.immersiveSpaceState = .closed
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview Provider
