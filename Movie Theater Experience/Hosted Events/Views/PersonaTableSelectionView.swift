//
//  PersonaTableSelectionView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/16/25.
//

import Foundation
import SwiftUI

struct PersonaTableSelectionView: View {
    let event: CalendarEvent
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var personaManager: PersonaTableManager
    @State private var selectedTable: Int?

    var body: some View {
        VStack {
            Text("Choose Your Table")
                .font(.title2.bold())
            tableGrid
            joinButton
        }
        .padding()
    }

    private var tableGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))]) {
            ForEach(hostedEventManager.tables) { table in
                Button(action: { selectedTable = table.tableNumber }) {
                    VStack {
                        Text(table.tableName ?? "Table \(table.tableNumber)")
                        Text("\(table.participants.count)/\(table.maxSeats) seated")
                            .font(.caption)
                    }
                    .padding()
                    .background(selectedTable == table.tableNumber ? .blue.opacity(0.23) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedTable == table.tableNumber ? .blue : .gray, lineWidth: 2)
                    )
                }
                .disabled(table.isFull)
            }
        }
    }

    private var joinButton: some View {
        Button("Join Table") {
            guard let selectedTable = selectedTable else { return }
            Task {
                _ = await hostedEventManager.assignUserToTable(personaManager.participants.first?.userId ?? "", tableNumber: selectedTable)
            }
        }
        .disabled(selectedTable == nil)
        .buttonStyle(.borderedProminent)
        .font(.headline)
    }
}
