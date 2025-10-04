//
//  TableFaceTimeLinkSetupView.swift
//  Movie Theater Experience
//
//  UI for host to set up FaceTime links for each table
//

import SwiftUI

struct TableFaceTimeLinkSetupView: View {
    @EnvironmentObject private var hostedEventManager: HostedEventManager
    @State private var linkInputs: [Int: String] = [:]
    @State private var savingStates: [Int: Bool] = [:]
    @State private var showInstructions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    instructionsSection

                    if hostedEventManager.tables.isEmpty {
                        emptyStateView
                    } else {
                        tablesSection
                    }
                }
                .padding()
            }
            .navigationTitle("FaceTime Setup")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            loadExistingLinks()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Set Up Table FaceTime Links")
                .font(.title2.bold())

            Text("Create FaceTime links for each table so participants can join audio/video calls")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom)
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { showInstructions.toggle() }) {
                HStack {
                    Image(systemName: "info.circle.fill")
                    Text("How to Create FaceTime Links")
                    Spacer()
                    Image(systemName: showInstructions ? "chevron.up" : "chevron.down")
                }
                .font(.headline)
            }
            .buttonStyle(.bordered)

            if showInstructions {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Open the FaceTime app")
                    Text("2. Tap 'Create Link'")
                    Text("3. Copy the link")
                    Text("4. Paste it below for each table")
                    Text("5. Tap 'Save' for each table")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "table.furniture")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Tables Available")
                .font(.headline)

            Text("Tables will appear here once the event is set up")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Tables Section

    private var tablesSection: some View {
        VStack(spacing: 16) {
            ForEach(hostedEventManager.tables.sorted(by: { $0.tableNumber < $1.tableNumber })) { table in
                TableLinkCard(
                    table: table,
                    linkInput: Binding(
                        get: { linkInputs[table.tableNumber] ?? "" },
                        set: { linkInputs[table.tableNumber] = $0 }
                    ),
                    isSaving: savingStates[table.tableNumber] ?? false,
                    onSave: {
                        await saveLink(for: table.tableNumber)
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func loadExistingLinks() {
        for table in hostedEventManager.tables {
            if let existingLink = table.faceTimeLinkURL {
                linkInputs[table.tableNumber] = existingLink
            }
        }
    }

    private func saveLink(for tableNumber: Int) async {
        guard let link = linkInputs[tableNumber], !link.isEmpty else {
            print("⚠️ No link provided for table \(tableNumber)")
            return
        }

        savingStates[tableNumber] = true

        let result = await hostedEventManager.updateTableFaceTimeLink(tableNumber, faceTimeURL: link)

        savingStates[tableNumber] = false

        switch result {
        case .success:
            print("✅ FaceTime link saved for table \(tableNumber)")
        case .failure(let error):
            print("❌ Failed to save link: \(error)")
        }
    }
}

// MARK: - Table Link Card

struct TableLinkCard: View {
    let table: EventTable
    @Binding var linkInput: String
    let isSaving: Bool
    let onSave: () async -> Void

    var hasExistingLink: Bool {
        table.faceTimeLinkURL != nil && !(table.faceTimeLinkURL?.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(table.teamName ?? "Table \(table.tableNumber)")
                        .font(.headline)

                    Text("\(table.participants.count)/\(table.maxSeats) participants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if hasExistingLink {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }

            // Link Input
            TextField("Paste FaceTime link here", text: $linkInput)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .font(.caption)

            // Actions
            HStack {
                Button("Open FaceTime") {
                    if let url = URL(string: "facetime://") {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Save") {
                    Task {
                        await onSave()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(linkInput.isEmpty || isSaving)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Preview

#if DEBUG
struct TableFaceTimeLinkSetupView_Previews: PreviewProvider {
    static var previews: some View {
        TableFaceTimeLinkSetupView()
            .environmentObject(HostedEventManager.shared)
    }
}
#endif
