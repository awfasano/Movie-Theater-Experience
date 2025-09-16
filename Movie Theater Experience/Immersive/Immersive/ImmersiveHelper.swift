//
//  ImmersiveHelper.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/23/25.
//

import Foundation
import SwiftUI
import RealityKit


/// Represents the possible states of an immersive space
enum ImmersiveSpaceState: Equatable {
    case open
    case closed
    case transitioning(TransitionType)
    
    enum TransitionType: Equatable {
        case opening
        case closing
        case cleaning
    }
    
    var isTransitioning: Bool {
        if case .transitioning(_) = self {
            return true
        }
        return false
    }
}

/// Protocol for components that need to respond to immersive space lifecycle events
protocol ImmersiveSpaceDelegate: AnyObject {
    func immersiveSpaceWillOpen()
    func immersiveSpaceDidOpen()
    func immersiveSpaceWillClose()
    func immersiveSpaceDidClose()
    func immersiveSpaceDidFailToOpen()
}

/// Default implementations to make the protocol easier to adopt
extension ImmersiveSpaceDelegate {
    func immersiveSpaceWillOpen() {}
    func immersiveSpaceDidOpen() {}
    func immersiveSpaceWillClose() {}
    func immersiveSpaceDidClose() {}
    func immersiveSpaceDidFailToOpen() {}
}

/// Wrapper to hold weak references to delegates

class WeakDelegate {
    weak var delegate: ImmersiveSpaceDelegate?
    
    init(_ delegate: ImmersiveSpaceDelegate) {
        self.delegate = delegate
    }
}
