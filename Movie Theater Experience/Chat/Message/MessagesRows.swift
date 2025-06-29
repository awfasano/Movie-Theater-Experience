//
//  MessagesRows.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/31/25.
//

import Foundation
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let isFirstInSequence: Bool
    let showTimestamp: Bool
    let opacity: Double
    
    var body: some View {
        ChatBubble(
            message: message,
            // A message is considered incoming if its sender ID is not the current user.
            showTimestamp: showTimestamp,
            isFirstInSequence: isFirstInSequence,
            opacity: opacity
        )
    }
}
