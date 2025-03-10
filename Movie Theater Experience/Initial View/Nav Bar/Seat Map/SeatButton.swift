//
//  SeatButton.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 1/8/25.
//


import SwiftUI
import RealityKit

// Cache seat geometry to avoid recalculation
struct SeatGeometry {
    static let width: CGFloat = 50
    static let height: CGFloat = 50
    static let spacing: CGFloat = 10
}

// Separate modifier for selection effects to improve performance
struct SelectionModifier: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        if isSelected {
            content
                .background(Circle().fill(Color.green.opacity(0.2)))
                .shadow(color: .green.opacity(0.3), radius: 5)
        } else {
            content
        }
    }
}

// Simplified seat button with minimal state dependencies
struct SeatButton: View {
    let rowNumber: Int
    let seatNumber: Int
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            makeButtonImage()
                .frame(width: SeatGeometry.width, height: SeatGeometry.height)
                .modifier(SelectionModifier(isSelected: isSelected))
        }
    }
    
    @ViewBuilder
    private func makeButtonImage() -> some View {
        Image(systemName: "chair.lounge.fill")
            .foregroundColor(isSelected ? .green : .blue)
            .font(.system(size: 24))
    }
}

// Memory efficient row view
struct TheaterRowView: View {
    let row: TheaterRow
    let selectedRow: Int
    let selectedSeat: Int
    let onSeatSelect: (Int, Int, Entity) -> Void
    
    var body: some View {
        HStack(spacing: SeatGeometry.spacing) {
            // Static row label
            Text("Row \(row.rowNumber)")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .leading)
            
            // Optimized seats layout
            ForEach(row.seats) { seat in
                SeatButton(
                    rowNumber: row.rowNumber,
                    seatNumber: seat.seatNumber,
                    isSelected: selectedRow == row.rowNumber && selectedSeat == seat.seatNumber,
                    onSelect: { onSeatSelect(row.rowNumber, seat.seatNumber, seat.entity) }
                )
            }
            
            Spacer(minLength: 0)
        }
    }
}



