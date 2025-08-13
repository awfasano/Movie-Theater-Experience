//
//  WorldBuilderView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/13/25.
//

import Foundation
import SwiftUI
import RealityKit
import RealityKitContent

struct WorldBuilderView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var immersiveSpaceManager: ImmersiveSpaceManager
    @EnvironmentObject private var windowManager: WindowManager
    @StateObject private var worldBuilder = WorldBuilderManager.shared
    
    var body: some View {
        RealityView { content in
            // Setup the world builder scene
            await worldBuilder.setupScene(in: content)
        } update: { content in
            // Handle updates to the scene
            worldBuilder.updateScene(in: content)
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    worldBuilder.handleTap(on: value.entity, at: value.location3D)
                }
        )
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    worldBuilder.handleDrag(entity: value.entity, translation: value.translation3D)
                }
        )
        .onAppear {
            Task {
                await worldBuilder.initialize()
                // Connect to Gemini Live when ready
                await worldBuilder.connectVoiceInterface()
            }
        }
        .onDisappear {
            Task {
                await worldBuilder.cleanup()
            }
        }
    }
}
