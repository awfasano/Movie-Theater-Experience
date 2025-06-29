//
//  FlowLayout.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/2/25.
//

import Foundation
import RealityKit
import SwiftUI

/// A layout that flows items like a tag cloud
struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        
        for (index, position) in result.positions.enumerated() {
            let point = CGPoint(x: position.x + bounds.minX, y: position.y + bounds.minY)
            subviews[index].place(at: point, proposal: result.sizes[index])
        }
    }
    
    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], sizes: [ProposedViewSize], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [ProposedViewSize] = []
        
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth, currentX > 0 {
                // Move to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            sizes.append(ProposedViewSize(width: size.width, height: size.height))
            
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        
        return (positions, sizes, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}
