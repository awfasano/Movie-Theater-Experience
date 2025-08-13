//
//  WorldBuilderControlsView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation
import SwiftUICore

struct WorldBuilderControlsView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var worldBuilder: WorldBuilderManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "cube.fill")
                    .font(.title)
                Text("World Builder")
                    .font(.title)
                Spacer()
            }
            .padding()
            
            // Voice Status
            HStack {
                Circle()
                    .fill(worldBuilder.isVoiceActive ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(worldBuilder.isVoiceActive ? "Voice Active" : "Voice Inactive")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            
            // Transcript
            if !worldBuilder.voiceTranscript.isEmpty {
                VStack(alignment: .leading) {
                    Text("You said:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(worldBuilder.voiceTranscript)
                        .font(.body)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
            }
            
            // Environment Selector
            VStack(alignment: .leading) {
                Text("Environment")
                    .font(.headline)
                
                Picker("Environment", selection: $worldBuilder.environment) {
                    ForEach(EnvironmentPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue.capitalized)
                            .tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: worldBuilder.environment) { _, newValue in
                    Task {
                        await worldBuilder.loadEnvironment(newValue)
                    }
                }
            }
            .padding(.horizontal)
            
            // Object Count
            HStack {
                Image(systemName: "cube.transparent")
                Text("\(worldBuilder.placedObjects.count) objects placed")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            
            // Generation Status
            if worldBuilder.isGeneratingObject {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating 3D model...")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await worldBuilder.connectVoiceInterface()
                    }
                }) {
                    Label("Start Voice Control", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(worldBuilder.isVoiceActive)
                
                Button(action: {
                    // Save world
                }) {
                    Label("Save World", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(width: 400, height: 600)
    }
}
