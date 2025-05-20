//
//  SeekSliderView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 5/27/25.
//

import Foundation
import SwiftUI

struct SeekSliderView: View {
    private let videoSyncService   = VideoSyncService.shared // Use the shared instance
    @State private var sliderPosition: Double = 0.0
    @State private var isScrubbing: Bool = false
    let duration: Double // This is also an expected parameter

    var body: some View {
        ThinTrackSlider(
            value: $sliderPosition,
            range: 0...(duration > 0 ? duration : 1.0),
            onEditingChanged: { scrubbingInProgress in
                isScrubbing = scrubbingInProgress
                if !scrubbingInProgress { // Scrubbing ended
                    // sliderPosition is already updated via the @Binding in ThinTrackSlider's Coordinator
                    Task {
                        await videoSyncService.handleSeek(to: sliderPosition)
                    }
                }
            }
        )
        .onChange(of: videoSyncService.currentTime) { _, newTime in
            if !isScrubbing { // Only update slider if user is not actively scrubbing
                sliderPosition = newTime
            }
        }
        .onAppear {
            // Initialize sliderPosition with the current time from the sync service
            sliderPosition = videoSyncService.currentTime
        }
        // Ensure that the view has a defined height, otherwise ThinTrackSlider might not render correctly.
        // You might need to adjust this based on your layout.
        .frame(height: 40) // Example height, adjust as needed
    }
}
