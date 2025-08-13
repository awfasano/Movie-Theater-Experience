//
//  WorldBuilderLaunchView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation

struct WorldBuilderLaunchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var immersiveSpaceManager: ImmersiveSpaceManager
    
    @State private var isInWorldBuilder = false
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 80))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            Text("World Builder")
                .font(.largeTitle)
                .bold()
            
            Text("Create immersive 3D worlds with voice commands and AI")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: toggleWorldBuilder) {
                Label(
                    isInWorldBuilder ? "Exit World Builder" : "Enter World Builder",
                    systemImage: isInWorldBuilder ? "xmark.circle" : "cube.fill"
                )
                .font(.title3)
                .padding()
            }
            .controlSize(.extraLarge)
            .buttonStyle(.borderedProminent)
            .disabled(!immersiveSpaceManager.canTransition)
            
            if isInWorldBuilder {
                Text("Voice control is active. Start speaking to create!")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func toggleWorldBuilder() {
        Task {
            if isInWorldBuilder {
                // Exit world builder
                await dismissImmersiveSpace()
                isInWorldBuilder = false
            } else {
                // Enter world builder
                let success = await appModel.switchToSpace(AppModel.worldBuilderSpaceID)
                if success {
                    await openImmersiveSpace(id: AppModel.worldBuilderSpaceID)
                    openWindow(id: "worldBuilderControls")
                    isInWorldBuilder = true
                }
            }
        }
    }
}
