//
//  AppModel.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 9/20/24.
//

import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    // Shared seat selection data
    var sharedSelection = SharedSeatSelection()
}
