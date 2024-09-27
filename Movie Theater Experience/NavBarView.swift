//
//  NavBarView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/24/24.
//

import Foundation
import SwiftUI

struct NavBarView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @Environment(AppModel.self) private var appModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        HStack(spacing: 40) { // Adjust spacing as needed
            // Chat Button
            Button(action: {
                openWindow(id: "chatWindow")
            }) {
                Image(systemName: "message.fill")
                    .resizable()
                    .frame(width: 30, height: 30)
            }

            // Emoji Button
            Button(action: {
                openWindow(id: "emojiWindow")
            }) {
                Image(systemName: "face.smiling.fill")
                    .resizable()
                    .frame(width: 30, height: 30)
            }

            // Seat Map Button
            Button(action: {
                openWindow(id: "seatMap")
            }) {
                Image(systemName: "chair.fill")
                    .resizable()
                    .frame(width: 30, height: 30)
            }

            // Pop-out Movie Screen Button
            Button(action: {
                // Implement pop-out action
            }) {
                Image(systemName: "rectangle.on.rectangle")
                    .resizable()
                    .frame(width: 30, height: 30)
            }

            // Toggle Immersive Space Button
            Button {
                Task { @MainActor in
                    switch appModel.immersiveSpaceState {
                        case .open:
                            appModel.immersiveSpaceState = .inTransition
                            await dismissImmersiveSpace()
                            dismissWindow(id: "navBar")


                            // State will be set to .closed in ImmersiveView.onDisappear()

                        case .closed:

                            appModel.immersiveSpaceState = .inTransition
                            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                                case .opened:
                                    // State will be set to .open in ImmersiveView.onAppear()
                                    break
                                case .userCancelled, .error:
                                    appModel.immersiveSpaceState = .closed
                                @unknown default:
                                    appModel.immersiveSpaceState = .closed
                            }

                        case .inTransition:
                            break
                    }
                }
            } label: {
                Image(systemName: appModel.immersiveSpaceState == .open ? "figure.walk" : "door.left.hand.open")
                    .resizable()
                    .frame(width: 30, height: 30)
            }
            .disabled(appModel.immersiveSpaceState == .inTransition)
            .animation(.none, value: 0)
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.9))
        .cornerRadius(10)
    }

    // Your toggle function for immersive space

}
