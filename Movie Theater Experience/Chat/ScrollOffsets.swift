//
//  ScrollOffsets.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 11/18/24.
//

import Foundation
import SwiftUI
import FirebaseFirestore

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollViewOffsetModifier: ViewModifier {
    let coordinateSpace: String
    let completion: (CGFloat) -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named(coordinateSpace)).minY
                        )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self, perform: completion)
    }
}
