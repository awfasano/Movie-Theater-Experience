//
//  ThinTrackSliderControl.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 4/29/25.
//  Updated by Gemini on 6/24/25
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

struct ThinTrackSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> ThinTrackSliderControl {
        let slider = ThinTrackSliderControl(frame: .zero)

        // —— appearance ——
        slider.minimumTrackTintColor = .purple
        slider.maximumTrackTintColor = UIColor.purple.withAlphaComponent(0.3)
        slider.thumbTintColor       = .white
        slider.setThumbImage(UIImage(systemName: "circle.fill"), for: .normal)

        // —— value & bounds ——
        slider.isContinuous = true                     // updates while dragging
        slider.minimumValue  = Float(range.lowerBound)
        slider.maximumValue  = Float(range.upperBound)
        slider.value         = Float(value)

        // —— events ——
        slider.addTarget(context.coordinator,
                         action: #selector(Coordinator.valueChanged(_:)),
                         for: .valueChanged)

        // **BEGIN scrubbing**
        slider.addTarget(context.coordinator,
                         action: #selector(Coordinator.didBeginScrubbing(_:)),
                         for: .touchDown)

        // **END scrubbing**
        slider.addTarget(context.coordinator,
                         action: #selector(Coordinator.didEndScrubbing(_:)),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])

        return slider
    }

    func updateUIView(_ uiView: ThinTrackSliderControl, context: Context) {
        // Update rail bounds ONLY when they actually change,
        // and never while the user is still dragging.
        if !uiView.isTracking &&
           (uiView.maximumValue != Float(range.upperBound) ||
            uiView.minimumValue != Float(range.lowerBound)) {

            uiView.minimumValue = Float(range.lowerBound)
            uiView.maximumValue = Float(range.upperBound)
        }

        // Keep the thumb in sync when *we’re* driving it.
        if !uiView.isTracking {
            uiView.setValue(Float(value), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: ThinTrackSlider
        init(_ parent: ThinTrackSlider) { self.parent = parent }

        // Slider moved → update binding
        @objc func valueChanged(_ sender: UISlider) {
            parent.value = Double(sender.value)
        }

        // Finger down
        @objc func didBeginScrubbing(_ sender: UISlider) {
            parent.onEditingChanged(true)          // tells the VM: “pause & remember state”
        }

        // Finger up / cancelled
        @objc func didEndScrubbing(_ sender: UISlider) {
            parent.onEditingChanged(false)         // VM seeks & (optionally) resumes play
        }
    }
}
