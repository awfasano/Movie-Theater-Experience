//
//  SeatSelectionWindow.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 3/16/25.
//

import Foundation
import SwiftUICore
import SwiftUI


struct SeatSelectionWindow: View {
    @Binding var currentSeat: String
    var availableSeats: [String]
    var onSeatSelected: (String) -> Void
    @Environment(\.dismissWindow) private var dismissWindow
    
    var body: some View {
        VStack {
            // Window Header
            HStack {
                Spacer()
                Text("Select Seat")
                    .font(.headline)
                    .padding(.top, 8)
                Spacer()
                
                Button(action: {
                    dismissWindow()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .padding(.horizontal)
            
            Divider()
            
            // Seat selection grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 16) {
                    ForEach(availableSeats, id: \.self) { seat in
                        Button {
                            currentSeat = seat
                            onSeatSelected(seat)
                            // Optional: close window after selection
                            // dismissWindow()
                        } label: {
                            VStack {
                                Image(systemName: currentSeat == seat ? "chair.lounge.fill" : "chair.lounge")
                                    .font(.system(size: 32))
                                    .foregroundColor(currentSeat == seat ? .white : .primary)
                                    .frame(width: 60, height: 60)
                                    .background(currentSeat == seat ? Color.blue : Color.secondary.opacity(0.2))
                                    .clipShape(Circle())
                                
                                Text(seat.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.callout)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(currentSeat == seat ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 320, height: 400)
    }
}
