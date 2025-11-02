//
//  MessagePositionTracker.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/26/25.
//

import Foundation
import CoreGraphics

class MessagePositionTracker: ObservableObject {
    @Published private var messageFrames: [String: CGRect] = [:]
    
    func updateFrame(_ frame: CGRect, for messageId: String) {
        messageFrames[messageId] = frame
    }
    
    func getFrame(for messageId: String) -> CGRect? {
        return messageFrames[messageId]
    }
}

