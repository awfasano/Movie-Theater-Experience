//
//  TimeLineline.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/31/25.
//

import Foundation
import SwiftUI
import RealityKit

struct TimelineLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        return path
    }
}
