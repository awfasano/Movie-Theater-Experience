//
//  Enhanced PersonaTableSelectionView.swift
//  Movie Theater Experience
//
//  Table selection with SharePlay integration
//

import SwiftUI

struct PersonaTableSelectionView: View {
    let event: CalendarEvent
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @EnvironmentObject private var personaManager: PersonaTableManager
    @State private var selectedTable: Int?
    @State private var isJoining = false
    @State private var showError = false
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    tableGrid
                    joinButton
                }
                .padding()
            }
            .navigationTitle("Choose Your Table")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error Joining Table", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Select a table to join \(event.title)")
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
            
            Text("Choose wisely - you'll be collaborating with your tablemates!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if hostedEventManager.sharePlayActive {
                HStack(spacing: 8) {
                    Image(systemName: "shareplay")
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SharePlay Active")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                        
                        Text("Real-time sync with \(TriviaSharePlayManager.shared.participants.count) participants")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "shareplay")
                        .foregroundColor(.orange)
                    
                    Text("SharePlay will activate when you join")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(12)
                .background(.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private var tableGrid: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 160, maximum: 200))
        ], spacing: 16) {
            ForEach(hostedEventManager.tables, id: \.tableNumber) { table in
                tableCard(for: table)
            }
        }
    }
    
    private func tableCard(for table: EventTable) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedTable = table.tableNumber
            }
        } label: {
            VStack(spacing: 16) {
                // Table name and icon
                VStack(spacing: 8) {
                    Image(systemName: "table.furniture")
                        .font(.title2)
                        .foregroundColor(iconColor(for: table))
                    
                    Text(table.teamName ?? "Table \(table.tableNumber)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                
                // Capacity information
                VStack(spacing: 8) {
                    HStack {
                        Text("Capacity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(table.participants.count)/\(table.maxSeats)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    ProgressView(value: Float(table.participants.count), total: Float(table.maxSeats))
                        .progressViewStyle(LinearProgressViewStyle(tint: progressColor(for: table)))
                        .frame(height: 6)
                        .cornerRadius(3)
                }
                
                // Status indicator
                statusIndicator(for: table)
            }
            .padding(20)
            .frame(minHeight: 160)
            .frame(maxWidth: .infinity)
            .background(backgroundColor(for: table))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor(for: table), lineWidth: strokeWidth(for: table))
            )
            .cornerRadius(16)
            .scaleEffect(selectedTable == table.tableNumber ? 1.02 : 1.0)
        }
        .disabled(table.isFull)
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3), value: selectedTable)
    }
    
    private func statusIndicator(for table: EventTable) -> some View {
        Group {
            if table.isFull {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("FULL")
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
                .font(.caption)
                
            } else if selectedTable == table.tableNumber {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                    Text("SELECTED")
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                .font(.caption)
                
            } else {
                HStack {
                    Image(systemName: "circle")
                        .foregroundColor(.green)
                    Text("AVAILABLE")
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                .font(.caption)
            }
        }
    }

    private var joinButton: some View {
        VStack(spacing: 12) {
            if let selectedTable = selectedTable {
                let table = hostedEventManager.tables.first { $0.tableNumber == selectedTable }
                
                Text("Join \(table?.teamName ?? "Table \(selectedTable)")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button {
                guard let selectedTable = selectedTable else { return }
                joinTable(selectedTable)
            } label: {
                HStack(spacing: 12) {
                    if isJoining {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "person.badge.plus")
                        Text("Join Table")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(buttonBackground)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(selectedTable == nil || isJoining)
            .scaleEffect(selectedTable != nil ? 1.0 : 0.95)
            .animation(.spring(response: 0.3), value: selectedTable)
        }
    }
    
    private var buttonBackground: Color {
        if selectedTable != nil && !isJoining {
            return .blue
        } else {
            return .gray
        }
    }
    
    // MARK: - Actions
    
    private func joinTable(_ tableNumber: Int) {
        isJoining = true
        
        Task {
            let currentUserId = AppModel.shared.currentUserId
            let result = await hostedEventManager.assignUserToTable(currentUserId, tableNumber: tableNumber)
            
            await MainActor.run {
                isJoining = false
                
                switch result {
                case .success:
                    print("✅ Successfully joined table \(tableNumber)")
                    dismiss()
                    
                case .failure(let error):
                    print("❌ Failed to join table: \(error)")
                    errorMessage = getErrorMessage(for: error)
                    showError = true
                }
            }
        }
    }
    
    private func getErrorMessage(for error: HostedEventError) -> String {
        switch error {
        case .eventNotFound:
            return "Event not found. Please try again."
        case .tableAssignmentFailed:
            return "Unable to join table. It may be full or unavailable."
        case .joinFailed:
            return "Failed to join the event. Please check your connection."
        case .insufficientPermissions:
            return "You don't have permission to join this event."
        case .unknown:
            return "An unexpected error occurred. Please try again."
        }
    }
    
    // MARK: - Helper Methods
    
    private func backgroundColor(for table: EventTable) -> Color {
        if table.isFull {
            return .gray.opacity(0.1)
        } else if selectedTable == table.tableNumber {
            return .blue.opacity(0.15)
        } else {
            return .gray.opacity(0.05)
        }
    }
    
    private func borderColor(for table: EventTable) -> Color {
        if table.isFull {
            return .gray.opacity(0.3)
        } else if selectedTable == table.tableNumber {
            return .blue
        } else {
            return .gray.opacity(0.2)
        }
    }
    
    private func strokeWidth(for table: EventTable) -> CGFloat {
        if selectedTable == table.tableNumber {
            return 2
        } else {
            return 1
        }
    }
    
    private func iconColor(for table: EventTable) -> Color {
        if table.isFull {
            return .gray
        } else if selectedTable == table.tableNumber {
            return .blue
        } else {
            return .green
        }
    }
    
    private func progressColor(for table: EventTable) -> Color {
        if table.isFull {
            return .red
        } else if table.participants.count >= table.maxSeats - 1 {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PersonaTableSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleEvent = CalendarEvent(
            title: "Friday Night Trivia",
            description: "Test your knowledge!",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            timeZone: TimeZone.current.identifier,
            eventType: .hostedTrivia,
            status: .scheduled
        )
        
        PersonaTableSelectionView(event: sampleEvent)
            .environmentObject(HostedEventManager.shared)
            .environmentObject(PersonaTableManager())
    }
}
#endif
