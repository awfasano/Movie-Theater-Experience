import SwiftUI
import RealityKit

struct SeatSelectionPanel: View {
    @Binding var currentSeat: String
    var onSeatSelected: (String) -> Void
    var availableSeats: [String]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(availableSeats, id: \.self) { seat in
                    Button {
                        currentSeat = seat
                        onSeatSelected(seat)
                    } label: {
                        HStack {
                            Image(systemName: currentSeat == seat ? "chair.lounge.fill" : "chair.lounge")
                            Text(seat.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(currentSeat == seat ? .blue : .secondary.opacity(0.5))
                }
            }
            .padding()
        }
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}
