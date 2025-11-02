import CoreGraphics

struct FlowLayoutEngine {
    let spacing: CGFloat
    
    struct Result {
        let positions: [CGPoint]
        let totalHeight: CGFloat
    }
    
    func layout(sizes: [CGSize], maxWidth: CGFloat) -> Result {
        guard !sizes.isEmpty else {
            return Result(positions: [], totalHeight: 0)
        }
        
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for size in sizes {
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        
        let totalHeight = currentY + lineHeight
        return Result(positions: positions, totalHeight: totalHeight)
    }
}
