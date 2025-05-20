//
//  SeatButtonStyle.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 5/3/25.
//

import Foundation
import SwiftUI

struct SeatButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22)) // Consistent font size
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .foregroundColor(isSelected ? .green : .primary) // Text color changes based on selection
            .background(
                RoundedRectangle(cornerRadius: 10) // Slightly smaller radius
                    .fill(.regularMaterial) // Use regular material for background
                    .shadow(color: isSelected ? .green.opacity(0.65) : .black.opacity(0.2), // Conditional shadow
                            radius: isSelected ? 4 : 2, x: 0, y: isSelected ? 1 : 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.green : Color.secondary.opacity(0.4), // Conditional border
                                    lineWidth: isSelected ? 1.5 : 1) // Thicker border when selected
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0) // Scale down slightly when pressed
            // Animate the scale effect for press interaction
            .animation(.smooth(duration: 0.25), value: configuration.isPressed)
            // Animate changes related to the isSelected state (color, shadow, border)
            .animation(.smooth(duration: 0.4), value: isSelected)
    }
}
