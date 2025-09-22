//
//  TriviaSpaceView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import SwiftUI
import RealityKit

struct TriviaSpaceView: View {
    @EnvironmentObject private var personaManager: PersonaTableManager
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RealityView { content in
            setupTriviaSpace(content)
        } update: { content in
            updatePersonaPositions(content)
        }
        .overlay(alignment: .topTrailing) {
            hostControlsButton
        }
        .overlay(alignment: .bottomLeading) {
            participantInfo
        }
    }
    
    private func setupTriviaSpace(_ content: RealityViewContent) {
        // Load base space geometry, add table markers, initialize persona positions, setup host position
        // If you need async operations, use Task { } to wrap them
    }
    
    private func updatePersonaPositions(_ content: RealityViewContent) {
        // Update persona positions based on personaManager.personaPositions, animate persona movements, update indicators
        // If you need async operations, use Task { } to wrap them
    }
    
    private var hostControlsButton: some View {
        Button {
            openWindow(id: "hostControls")
        } label: {
            Label("Host Controls", systemImage: "person.crop.square.filled.and.at.rectangle")
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }
    
    private var participantInfo: some View {
        VStack(alignment: .leading) {
            Text("Participants: \(hostedEventManager.participants.count)")
                .font(.caption)
            // More info can be added here
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
