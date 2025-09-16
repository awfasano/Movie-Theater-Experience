//
//  EnhancedEventView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import SwiftUI

struct EnhancedEventView: View {
    let event: CalendarEvent
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @State private var showingTableSelection = false

    var body: some View {
        VStack {
            eventHeader
            eventTypeBadge
            if event.isHostedEvent { capacitySection }
            joinButton
        }
        .sheet(isPresented: $showingTableSelection) {
            PersonaTableSelectionView(event: event)
                .environmentObject(hostedEventManager)
        }
    }

    private var eventHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.headline)
            Text(event.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var eventTypeBadge: some View {
        Label(event.eventType.rawValue.capitalized, systemImage: "person.3")
            .padding(4)
            .background(.blue.opacity(0.13))
            .clipShape(Capsule())
            .font(.caption)
    }

    private var capacitySection: some View {
        HStack {
            Text("\(event.currentParticipants)/\(event.maxParticipants) joined")
                .font(.caption)
            if event.isFull {
                Text("Full").foregroundColor(.red).font(.caption)
            }
        }
    }

    private var joinButton: some View {
        Button(action: { showingTableSelection = true }) {
            Text("Join Event")
                .font(.body.bold())
                .padding()
                .background(event.canJoin ? .green : .gray)
                .foregroundStyle(.white)
                .cornerRadius(8)
        }
        .disabled(!event.canJoin)
    }
}
