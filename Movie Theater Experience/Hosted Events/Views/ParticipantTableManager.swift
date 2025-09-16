//
//  ParticipantTableManager.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import SwiftUI

struct ParticipantTableManager: View {
    @EnvironmentObject private var hostedEventManager: HostedEventManager

    var body: some View {
        HStack {
            participantsList
            tablesGrid
        }
    }

    private var participantsList: some View {
        List(hostedEventManager.participants) { participant in
            Text(participant.userName)
        }
    }

    private var tablesGrid: some View {
        VStack {
            ForEach(hostedEventManager.tables) { table in
                HStack {
                    Text(table.tableName ?? "Table \(table.tableNumber)")
                    Button("Add Participant") {
                        // Call moveParticipant when needed
                    }
                }
            }
        }
    }
    
    private func moveParticipant(_ participant: EventParticipant, to table: EventTable) {
        Task {
            await hostedEventManager.moveParticipant(participant.userId, to: table.tableNumber)
        }
    }
}

