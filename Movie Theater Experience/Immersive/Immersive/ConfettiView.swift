//
//  ConfettiView.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 5/5/25.
//

import SwiftUI
import QuartzCore

// MARK: - ConfettiView
struct ConfettiView: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        // --- 1. Emitter layer ---
        let emitter = CAEmitterLayer()
        emitter.frame = view.bounds
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: 0)
        emitter.emitterSize = CGSize(width: view.bounds.width, height: 1)

        // --- 2. Confetti cell configuration ---
        let colors: [UIColor] = [.systemPink, .systemBlue, .systemGreen,
                                 .systemOrange, .systemPurple, .systemYellow]
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.birthRate      = 6
            cell.lifetime       = 6
            cell.lifetimeRange  = 1
            cell.velocity       = 180
            cell.velocityRange  = 60
            cell.emissionLongitude = .pi        // downward
            cell.emissionRange = .pi / 4        // spread
            cell.spin           = 3.5
            cell.spinRange      = 4
            cell.scale          = 0.6
            cell.scaleRange     = 0.3
            cell.color          = color.cgColor
            cell.contents       = makeConfettiImage().cgImage
            return cell
        }

        view.layer.addSublayer(emitter)

        // --- 3. Stop after 3 s to keep it light ---
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            emitter.birthRate = 0
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// A tiny 6×6 rectangle image used as particle texture
    private func makeConfettiImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 6))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 6, height: 6))
        }
    }
}
