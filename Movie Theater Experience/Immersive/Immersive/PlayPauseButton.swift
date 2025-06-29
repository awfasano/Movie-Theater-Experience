//
//  PlayPauseButton.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 5/27/25.
//

import Foundation
import SwiftUI

struct PlayPauseButton: View {
    let videoSyncService = VideoSyncService.shared
    
    var body: some View {
        Button {
            Task {
                await videoSyncService.handlePlayPauseToggle()
            }
        } label: {
            Image(systemName: videoSyncService.isPlaying ? "pause.fill" : "play.fill")
                .font(.title)
        }
    }
}
