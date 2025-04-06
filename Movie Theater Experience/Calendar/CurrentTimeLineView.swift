//
//  CurrentTimeLineView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/31/25.
//

import Foundation
import SwiftUI
import RealityKit

struct CurrentTimeLineView: View {
    let lineHeight: CGFloat
    let xPosition: CGFloat
    private let baseDepth: Double = 20
    
    var body: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: lineHeight))
        }
        .stroke(Color.red, lineWidth: 2)
        .offset(x: xPosition)
        .offset(z: baseDepth)
        .allowsHitTesting(false)
    }
}
