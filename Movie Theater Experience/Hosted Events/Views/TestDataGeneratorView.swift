//
//  TestDataGeneratorView.swift
//  Movie Theater Experience
//
//  UI for generating test data
//

import SwiftUI

struct TestDataGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isGenerating = false
    @State private var generationMessage = ""
    @State private var lastCreatedEvent: CalendarEvent?
    var onComplete: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    actionsSection

                    if !generationMessage.isEmpty {
                        messageSection
                    }

                    if let event = lastCreatedEvent {
                        eventPreviewSection(event: event)
                    }
                }
                .padding()
            }
            .navigationTitle("Test Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "testtube.2")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Test Data Generator")
                .font(.title2.bold())

            Text("Create test trivia events for development")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    await createSingleEvent()
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Single Event")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)

            Button {
                Task {
                    await createMultipleEvents()
                }
            } label: {
                HStack {
                    Image(systemName: "square.stack.3d.up.fill")
                    Text("Create 3 Events")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating)

            Divider()

            Button(role: .destructive) {
                Task {
                    await deleteAllEvents()
                }
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Delete All Test Events")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating)
        }
    }

    // MARK: - Message

    private var messageSection: some View {
        VStack(spacing: 8) {
            if isGenerating {
                ProgressView()
            }

            Text(generationMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .background(.gray.opacity(0.1))
                .cornerRadius(8)
        }
    }

    // MARK: - Event Preview

    private func eventPreviewSection(event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Created Event")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: event.eventIcon)
                        .foregroundColor(event.eventColor)
                    Text(event.title)
                        .font(.subheadline.bold())
                }

                Text("ID: \(event.id ?? "Unknown")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Tables: \(event.tableConfiguration?.maxTables ?? 0)")
                    .font(.caption)

                Text("Rounds: \(event.gameConfig?.totalRounds ?? 0)")
                    .font(.caption)

                Text("Starts: \(event.formattedTimeRange)")
                    .font(.caption)
            }
            .padding()
            .background(.green.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Actions Implementation

    private func createSingleEvent() async {
        isGenerating = true
        generationMessage = "Creating test event..."

        do {
            let event = try await TriviaTestDataGenerator.shared.createTestTriviaEvent()

            await MainActor.run {
                lastCreatedEvent = event
                generationMessage = "✅ Event created successfully!"
                onComplete?()
            }

            // Clear message after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                if generationMessage == "✅ Event created successfully!" {
                    generationMessage = ""
                }
            }
        } catch {
            await MainActor.run {
                generationMessage = "❌ Failed to create event: \(error.localizedDescription)"
            }
        }

        isGenerating = false
    }

    private func createMultipleEvents() async {
        isGenerating = true
        generationMessage = "Creating 3 test events..."

        do {
            let events = try await TriviaTestDataGenerator.shared.createMultipleTestEvents(count: 3)

            await MainActor.run {
                lastCreatedEvent = events.first
                generationMessage = "✅ Created \(events.count) events successfully!"
                onComplete?()
            }

            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                if generationMessage.contains("✅") {
                    generationMessage = ""
                }
            }
        } catch {
            await MainActor.run {
                generationMessage = "❌ Failed to create events: \(error.localizedDescription)"
            }
        }

        isGenerating = false
    }

    private func deleteAllEvents() async {
        isGenerating = true
        generationMessage = "Deleting all test events..."

        do {
            try await TriviaTestDataGenerator.shared.deleteAllTestEvents()

            await MainActor.run {
                lastCreatedEvent = nil
                generationMessage = "✅ All test events deleted"
                onComplete?()
            }

            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if generationMessage == "✅ All test events deleted" {
                    generationMessage = ""
                }
            }
        } catch {
            await MainActor.run {
                generationMessage = "❌ Failed to delete events: \(error.localizedDescription)"
            }
        }

        isGenerating = false
    }
}

// MARK: - Preview

#if DEBUG
struct TestDataGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        TestDataGeneratorView()
    }
}
#endif
