//
//  ThinTrackSliderControl.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 4/29/25.
//

import Foundation
import SwiftUI
import UIKit

// 1) Subclass UISlider to force a thin track
class ThinTrackSliderControl: UISlider {
    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        // desired rail height
        let railHeight: CGFloat = 3
        let yOffset = (bounds.height - railHeight) / 2
        return CGRect(x: 0, y: yOffset, width: bounds.width, height: railHeight)
    }
}

// 2) Wrap it in UIViewRepresentable
struct ThinTrackSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> ThinTrackSliderControl {
        let slider = ThinTrackSliderControl(frame: .zero)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.minimumTrackTintColor = .purple
        slider.maximumTrackTintColor = UIColor.purple.withAlphaComponent(0.3)
        slider.thumbTintColor = .white
        // keep the thumb a circle
        slider.setThumbImage(UIImage(systemName: "circle.fill"), for: .normal)
        slider.setThumbImage(UIImage(systemName: "circle.fill"), for: .highlighted)

        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        return slider
    }

    func updateUIView(_ uiView: ThinTrackSliderControl, context: Context) {
        uiView.value = Float(value)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: ThinTrackSlider
        init(_ parent: ThinTrackSlider) { self.parent = parent }

        @objc func valueChanged(_ sender: UISlider) {
            parent.value = Double(sender.value)
            parent.onEditingChanged(true)
        }
        @objc func touchUp(_ sender: UISlider) {
            parent.onEditingChanged(false)
        }
    }
}
