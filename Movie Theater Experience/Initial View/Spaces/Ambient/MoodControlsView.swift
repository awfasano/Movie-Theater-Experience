//
//  MoodControlsView.swift
//  Movie Theater Experience
//
//  Created for Ambient Focus Rooms feature.
//

import SwiftUI

struct MoodControlsView: View {
    @EnvironmentObject var moodController: AmbientMoodController

    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Title
            Text("Mood Controls")
                .font(.title2)
                .fontWeight(.semibold)

            // MARK: - Soundscape Picker
            VStack(alignment: .leading, spacing: 10) {
                Text("Soundscape")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(moodController.availableSoundscapes, id: \.self) { soundscape in
                            Button(action: {
                                moodController.switchSoundscape(to: soundscape)
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: soundscape.iconName)
                                        .font(.title2)
                                        .frame(width: 48, height: 48)
                                        .background(
                                            moodController.currentSoundscape == soundscape
                                                ? Color.blue.opacity(0.3)
                                                : Color.white.opacity(0.1)
                                        )
                                        .clipShape(Circle())

                                    Text(soundscape.displayName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(
                                moodController.currentSoundscape == soundscape
                                    ? .primary
                                    : .secondary
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            // MARK: - Volume Slider
            VStack(alignment: .leading, spacing: 8) {
                Text("Ambient Volume")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { moodController.ambientVolume },
                            set: { moodController.updateVolume($0) }
                        ),
                        in: 0...1
                    )
                    .tint(.blue)

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Lighting Mood
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Lighting")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Coming soon")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }

                HStack(spacing: 12) {
                    ForEach(LightingMood.allCases, id: \.self) { mood in
                        Button(action: {
                            moodController.setLightingMood(mood)
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: mood.iconName)
                                    .font(.body)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        moodController.lightingMood == mood
                                            ? Color.blue.opacity(0.3)
                                            : Color.white.opacity(0.1)
                                    )
                                    .clipShape(Circle())

                                Text(mood.rawValue)
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            moodController.lightingMood == mood
                                ? .primary
                                : .secondary
                        )
                        .opacity(0.6) // Dimmed to indicate coming soon
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 400, height: 350)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }
}
