//
//  SpacesChatWindow.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/10/25.
//

import Foundation
import SwiftUICore
import SwiftUI


struct SpacesChatWindow: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var selectedSpace: SelectedSpace
    @State private var viewModel: SpacesChatViewModel?
    @Environment(\.dismissWindow) private var dismissWindow
    
    var body: some View {
        VStack {
            // Window Header
            HStack {
                Spacer()
                Text("Space Chat")
                    .font(.headline)
                    .padding(.top, 8)
                Spacer()
                
                Button(action: {
                    dismissWindow()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .padding(.horizontal)
            
            Divider()
            
            if let viewModel = viewModel {
                // Use your existing ChatView with the space-specific view model
                ChatView(viewModel: viewModel)
            } else {
                ProgressView("Loading chat...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        // Initialize with current space ID
                        if let spaceId = currentSpaceId {
                            self.viewModel = SpacesChatViewModel(spaceId: spaceId)
                        }
                    }
            }
        }
    }
    
    // Get the current space ID from either source
    private var currentSpaceId: String? {
        return appModel.selectedSpace?.id ?? selectedSpace.space?.id
    }
}
