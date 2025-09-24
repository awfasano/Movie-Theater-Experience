//
//  Enhanced EnhancedEventView.swift
//  Movie Theater Experience
//
//  Event view with SharePlay integration
//

import SwiftUI

struct EnhancedEventView: View {
    let event: CalendarEvent
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @State private var showingTableSelection = false

    var body: some View {
        VStack(spacing: 12) {
            eventHeader
            eventTypeBadge
            
            if event.isHostedEvent {
                capacitySection
                sharePlayStatusIndicator
            }
            
            joinButton
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .sheet(isPresented: $showingTableSelection) {
            PersonaTableSelectionView(event: event)
                .environmentObject(hostedEventManager)
        }
    }

    private var eventHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(event.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventTypeBadge: some View {
        HStack {
            Label(event.eventType.rawValue.capitalized, systemImage: "person.3")
                .padding(6)
                .background(.blue.opacity(0.15))
                .clipShape(Capsule())
                .font(.caption)
                .foregroundColor(.blue)
            
            Spacer()
        }
    }

    private var capacitySection: some View {
        HStack {
            Text("\(event.currentParticipants)/\(event.maxParticipants) joined")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if event.isFull {
                Text("• FULL")
                    .font(.caption)
                    .foregroundColor(.red)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
    }
    
    private var sharePlayStatusIndicator: some View {
        HStack(spacing: 6) {
            if hostedEventManager.sharePlayActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                
                Text("SharePlay Active")
                    .font(.caption)
                    .foregroundColor(.green)
                    .fontWeight(.medium)
                
                Text("• \(TriviaSharePlayManager.shared.participants.count) connected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
            } else {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                
                Text("SharePlay will start when you join")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var joinButton: some View {
        Button(action: {
            showingTableSelection = true
        }) {
            HStack(spacing: 8) {
                Text("Join Event")
                    .font(.body.bold())
                
                if hostedEventManager.sharePlayActive {
                    Image(systemName: "shareplay")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(buttonBackgroundColor)
            .foregroundStyle(.white)
            .cornerRadius(8)
        }
        .disabled(!event.canJoin)
    }
    
    private var buttonBackgroundColor: Color {
        if !event.canJoin {
            return .gray
        } else if hostedEventManager.sharePlayActive {
            return LinearGradient(
                colors: [.green, .blue],
                startPoint: .leading,
                endPoint: .trailing
            ).toColor()
        } else {
            return .green
        }
    }
}

// MARK: - Helper Extension

extension LinearGradient {
    func toColor() -> Color {
        // This is a simplified approach - in practice you might want a different solution
        return .green
    }
}

// MARK: - Preview

#if DEBUG
struct EnhancedEventView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleEvent = CalendarEvent(
            title: "Friday Night Trivia",
            description: "Test your knowledge with friends!",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            timeZone: TimeZone.current.identifier,
            eventType: .hostedTrivia,
            status: .scheduled
        )
        
        VStack(spacing: 20) {
            EnhancedEventView(event: sampleEvent)
            EnhancedEventView(event: sampleEvent)
        }
        .padding()
        .environmentObject(HostedEventManager.shared)
        .previewLayout(.sizeThatFits)
    }
}
#endif
