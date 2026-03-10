//
//  AmbientSpaceSeeder.swift
//  Movie Theater Experience
//
//  Utility to seed ambient space documents into Firestore.
//  Designed to be called once from a debug button or on first launch.
//

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Seeder

final class AmbientSpaceSeeder {

    /// Template describing an ambient space to be seeded.
    private struct AmbientSpaceTemplate {
        let id: String
        let spaceName: String
        let description: String
        let tags: [String]
        let thumbnailURL: String
        let defaultSoundscape: String
    }

    /// The five ambient spaces to create.
    private static let ambientSpaces: [AmbientSpaceTemplate] = [
        AmbientSpaceTemplate(
            id: "rainy_rooftop_cafe",
            spaceName: "Rainy Rooftop Café",
            description: "A cozy rooftop terrace with gentle rain pattering on the awning. Perfect for deep focus work.",
            tags: ["ambient", "focus", "rain"],
            thumbnailURL: "",
            defaultSoundscape: "rain"
        ),
        AmbientSpaceTemplate(
            id: "mountain_cabin",
            spaceName: "Mountain Cabin Fireplace",
            description: "A warm wooden cabin with a crackling fireplace. The snow falls quietly outside.",
            tags: ["ambient", "relax", "fireplace"],
            thumbnailURL: "",
            defaultSoundscape: "fireplace"
        ),
        AmbientSpaceTemplate(
            id: "deep_space_observatory",
            spaceName: "Deep Space Observatory",
            description: "A sleek observation deck floating among the stars. The gentle hum of the station keeps you company.",
            tags: ["ambient", "focus", "spaceHum"],
            thumbnailURL: "",
            defaultSoundscape: "spaceHum"
        ),
        AmbientSpaceTemplate(
            id: "forest_stream",
            spaceName: "Forest Stream",
            description: "A peaceful forest clearing with a bubbling stream and birdsong. Nature at its most serene.",
            tags: ["ambient", "relax", "forest"],
            thumbnailURL: "",
            defaultSoundscape: "forest"
        ),
        AmbientSpaceTemplate(
            id: "ocean_sunset",
            spaceName: "Ocean Sunset",
            description: "A tranquil beach at golden hour. Waves lap gently at the shore as the sun dips below the horizon.",
            tags: ["ambient", "relax", "ocean"],
            thumbnailURL: "",
            defaultSoundscape: "ocean"
        )
    ]

    // MARK: - Public API

    /// Seeds all ambient spaces into Firestore, skipping any that already exist.
    /// Calls `onProgress` on the main actor with status messages.
    static func seedAmbientSpaces(onProgress: @escaping @MainActor (String) -> Void) async {
        let db = Firestore.firestore(database: FirebaseConfig.uploadsDatabaseID)
        let spacesCollection = db.collection("Spaces")

        await MainActor.run {
            onProgress("Starting ambient space seeding...")
        }

        var created = 0
        var skipped = 0
        var failed = 0

        for template in ambientSpaces {
            let docRef = spacesCollection.document(template.id)

            do {
                let snapshot = try await docRef.getDocument()

                if snapshot.exists {
                    let message = "Skipped \"\(template.spaceName)\" — already exists."
                    print(message)
                    await MainActor.run { onProgress(message) }
                    skipped += 1
                    continue
                }

                // Build document data matching SpaceData's Codable field names exactly.
                let spaceData: [String: Any] = [
                    "spaceName": template.spaceName,
                    "description": template.description,
                    "lastModified": FieldValue.serverTimestamp(),
                    "usdzURL": "",
                    "thumbnailURL": template.thumbnailURL,
                    "tags": template.tags,
                    "viewerXAdjustment": 0.0,
                    "viewerYAdjustment": 0.0,
                    "viewerZAdjustment": 0.0,
                    "currentUserCount": 0,
                    "maxUserCount": 50,
                    "seats": [] as [Any]
                ]

                try await docRef.setData(spaceData)

                // Create the default soundscape in a subcollection.
                let soundscapeRef = docRef.collection("soundscapes").document(template.defaultSoundscape)
                let soundscapeData: [String: Any] = [
                    "type": template.defaultSoundscape,
                    "audioURL": "",
                    "isDefault": true
                ]
                try await soundscapeRef.setData(soundscapeData)

                let message = "Created \"\(template.spaceName)\" with soundscape \"\(template.defaultSoundscape)\"."
                print(message)
                await MainActor.run { onProgress(message) }
                created += 1

            } catch {
                let message = "Failed to seed \"\(template.spaceName)\": \(error.localizedDescription)"
                print(message)
                await MainActor.run { onProgress(message) }
                failed += 1
            }
        }

        let summary = "Seeding complete — created: \(created), skipped: \(skipped), failed: \(failed)."
        print(summary)
        await MainActor.run { onProgress(summary) }
    }
}

// MARK: - Setup View

/// A simple debug view with a button to trigger ambient space seeding.
/// Add this temporarily to a settings tab or debug menu for one-time use.
struct AmbientSetupView: View {
    @State private var statusMessages: [String] = []
    @State private var isSeeding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ambient Space Setup")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Seeds the five ambient focus spaces into Firestore. Safe to run multiple times — existing spaces are skipped.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                startSeeding()
            } label: {
                HStack(spacing: 8) {
                    if isSeeding {
                        ProgressView()
                    }
                    Text(isSeeding ? "Seeding..." : "Seed Ambient Spaces")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSeeding)

            if !statusMessages.isEmpty {
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(statusMessages.enumerated()), id: \.offset) { _, message in
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(messageColor(for: message))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
    }

    // MARK: - Private

    private func startSeeding() {
        isSeeding = true
        statusMessages = []

        Task {
            await AmbientSpaceSeeder.seedAmbientSpaces { message in
                statusMessages.append(message)
            }
            isSeeding = false
        }
    }

    private func messageColor(for message: String) -> Color {
        if message.starts(with: "Failed") {
            return .red
        } else if message.starts(with: "Skipped") {
            return .yellow
        } else if message.starts(with: "Created") {
            return .green
        } else {
            return .secondary
        }
    }
}

#Preview(windowStyle: .automatic) {
    AmbientSetupView()
}
