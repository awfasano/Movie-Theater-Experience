//
//  MessagePreferenceKey.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/26/25.
//

import Foundation
import SwiftUICore

struct MessagePositionPreferenceKey: PreferenceKey {
    static var defaultValue: [MessagePosition] = []
    
    static func reduce(value: inout [MessagePosition], nextValue: () -> [MessagePosition]) {
        value.append(contentsOf: nextValue())
    }
}
