//
//  HostAnnouncementOverlay.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import SwiftUI

struct HostAnnouncementOverlay: View {
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @State private var currentAnnouncement: HostAnnouncement? = nil
    @State private var showingAnnouncement = false

    var body: some View {
        ZStack {
            if showingAnnouncement, let announcement = currentAnnouncement {
                VStack(spacing: 20) {
                    HStack {
                        Image(systemName: "crown.fill").foregroundColor(.yellow)
                        Text("Host Announcement").font(.headline).fontWeight(.bold)
                    }
                    Text(announcement.message)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .padding()
                    if announcement.type == .instruction {
                        Button("Got it!") { dismissAnnouncement() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(30)
                .background(.regularMaterial)
                .cornerRadius(20)
                .shadow(radius: 15)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(), value: showingAnnouncement)
        .onReceive(hostedEventManager.$gameState) { state in
            if let trigger = state?.trigger, !trigger.isEmpty {
                showAnnouncement(HostAnnouncement(message: trigger, type: .instruction, duration: 5, timestamp: Date()))
            }
        }
    }

    private func showAnnouncement(_ announcement: HostAnnouncement) {
        currentAnnouncement = announcement
        showingAnnouncement = true
        DispatchQueue.main.asyncAfter(deadline: .now() + announcement.duration) {
            dismissAnnouncement()
        }
    }

    private func dismissAnnouncement() {
        withAnimation { showingAnnouncement = false }
    }
}

struct HostAnnouncement: Identifiable {
    let id = UUID()
    let message: String
    let type: AnnouncementType
    let duration: TimeInterval
    let timestamp: Date
}

enum AnnouncementType {
    case general, instruction, celebration, warning
}
