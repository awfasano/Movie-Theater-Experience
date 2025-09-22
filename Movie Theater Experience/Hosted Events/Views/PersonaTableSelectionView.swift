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
        VStack(spacing: 20) {
            Text("Choose Your Table")
                .font(.title2.bold())
            
            tableGrid
            
            joinButton
        }
        .padding()
    }

    private var tableGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 16) {
            ForEach(hostedEventManager.tables, id: \.tableNumber) { table in
                Button {
                    selectedTable = table.tableNumber
                } label: {
                    VStack(spacing: 8) {
                        Text(table.tableName ?? "Table \(table.tableNumber)")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        
                        Text("\(table.participants.count)/\(table.maxSeats) seated")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if table.isFull {
                            Text("FULL")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(backgroundColor(for: table))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderColor(for: table), lineWidth: 2)
                    )
                }
                .disabled(table.isFull)
            }
        }
    }

    private var joinButton: some View {
        Button {
            guard let selectedTable = selectedTable else { return }
            Task {
                let currentUserId = AppModel.shared.currentUserId
                let result = await hostedEventManager.assignUserToTable(currentUserId, tableNumber: selectedTable)
                
                switch result {
                case .success:
                    print("Successfully joined table \(selectedTable)")
                case .failure(let error):
                    print("Failed to join table: \(error)")
                }
            }
        } label: {
            Text("Join Table")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .disabled(selectedTable == nil)
        .buttonStyle(.borderedProminent)
    }
    
    // MARK: - Helper Methods
    
    private func backgroundColor(for table: EventTable) -> Color {
        if table.isFull {
            return .gray.opacity(0.2)
        } else if selectedTable == table.tableNumber {
            return .blue.opacity(0.3)
        } else {
            return .clear
        }
    }
    
    private func borderColor(for table: EventTable) -> Color {
        if table.isFull {
            return .gray
        } else if selectedTable == table.tableNumber {
            return .blue
        } else {
            return .secondary
        }
    }
}
