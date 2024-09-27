import SwiftUI
import RealityKit

// Separate view for individual seats to reduce re-renders
struct SeatButton: View {
    let rowNumber: Int
    let seat: TheaterSeat
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            Image(systemName: "chair.lounge.fill")
                .foregroundColor(isSelected ? .green : .blue)
                .font(.system(size: 24))
                .frame(width: 50, height: 50)
                // Use opacity instead of Color.clear for better performance
                .background(isSelected ? Circle().fill(Color.green.opacity(0.2)) : nil)
                // Only apply shadow when selected
                .shadow(color: isSelected ? .green.opacity(0.3) : .clear, radius: 5)
        }
    }
}

// Separate view for row to prevent unnecessary re-renders
struct TheaterRowView: View {
    let row: TheaterRow
    let selectedRow: Int
    let selectedSeat: Int
    let onSeatSelect: (Int, Int, Entity) -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // Row label
            Text("Row \(row.rowNumber)")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .leading)
            
            // Seats
            ForEach(row.seats.sorted(by: { $0.seatNumber < $1.seatNumber })) { seat in
                SeatButton(
                    rowNumber: row.rowNumber,
                    seat: seat,
                    isSelected: selectedRow == row.rowNumber && selectedSeat == seat.seatNumber,
                    onSelect: { onSeatSelect(row.rowNumber, seat.seatNumber, seat.entity) }
                )
            }
            
            Spacer()
        }
    }
}

struct SeatMapView: View {
    @ObservedObject var sharedSelection = SharedSeatSelection.shared
    @ObservedObject var theatreEntityWrapper = TheatreEntityWrapper.shared
    @Environment(\.dismissWindow) private var dismissWindow
    
    // Use StateObject for better performance with large datasets
    @StateObject private var viewModel = SeatMapViewModel()
    
    var body: some View {
        VStack {
            // Header
            header
            
            // Content
            content
        }
        .background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
        .onAppear {
            viewModel.loadSeats(theatreEntityWrapper: theatreEntityWrapper)
        }
    }
    
    private var header: some View {
        HStack {
            Text("Theatre Map")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.leading)
            
            Spacer()
            
            Button(action: dismissWindow) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
                    .font(.system(size: 24))
            }
            .padding(.trailing)
        }
        .padding(.vertical)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .padding()
    }
    
    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingView
        } else if viewModel.organizedRows.isEmpty {
            emptyView
        } else {
            seatMapContent
        }
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView("Loading seats...")
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .padding()
    }
    
    private var emptyView: some View {
        VStack {
            Image(systemName: "chair.lounge.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue.opacity(0.6))
            
            Text("No seats available")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .padding()
    }
    
    private var seatMapContent: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(viewModel.organizedRows.sorted(by: { $0.rowNumber < $1.rowNumber })) { row in
                    TheaterRowView(
                        row: row,
                        selectedRow: sharedSelection.currentRow,
                        selectedSeat: sharedSelection.currentSeat,
                        onSeatSelect: selectSeat
                    )
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .padding()
    }
    
    private func selectSeat(row: Int, seat: Int, entity: Entity) {
        sharedSelection.selectedSeatEntity = entity
        sharedSelection.currentRow = row
        sharedSelection.currentSeat = seat
    }
}

// MARK: - ViewModel
class SeatMapViewModel: ObservableObject {
    @Published var organizedRows: [TheaterRow] = []
    @Published var isLoading = true
    
    func loadSeats(theatreEntityWrapper: TheatreEntityWrapper) {
        guard let seatsEntity = findSeatsEntity(in: theatreEntityWrapper) else {
            isLoading = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rows = self?.organizeSeats(from: seatsEntity) ?? []
            
            DispatchQueue.main.async {
                self?.organizedRows = rows
                self?.isLoading = false
            }
        }
    }
    
    private func findSeatsEntity(in wrapper: TheatreEntityWrapper) -> Entity? {
        guard let rootEntity = wrapper.entity,
              let innerRoot = rootEntity.children.first(where: { $0.name == "Root" }) else {
            return nil
        }
        return innerRoot.children.first(where: { $0.name == "seats" })
    }
    
    private func organizeSeats(from seatsEntity: Entity) -> [TheaterRow] {
        let rowEntities = seatsEntity.children
            .filter { $0.name.starts(with: "row_") }
            .sorted { entity1, entity2 in
                let num1 = extractNumber(from: entity1.name) ?? 0
                let num2 = extractNumber(from: entity2.name) ?? 0
                return num1 < num2
            }
        
        return rowEntities.compactMap { rowEntity in
            guard let rowNumber = extractNumber(from: rowEntity.name) else { return nil }
            
            let seats = rowEntity.children
                .filter { $0.name.starts(with: "Cube_") }
                .compactMap { cubeEntity -> TheaterSeat? in
                    guard let seatNumber = extractNumber(from: cubeEntity.name) else { return nil }
                    return TheaterSeat(
                        id: "seat_\(rowNumber)_\(seatNumber)",
                        entity: cubeEntity,
                        seatNumber: seatNumber
                    )
                }
                .sorted { $0.seatNumber < $1.seatNumber }
            
            guard !seats.isEmpty else { return nil }
            
            return TheaterRow(
                id: "row_\(rowNumber)",
                entity: rowEntity,
                rowNumber: rowNumber,
                seats: seats
            )
        }
    }
    
    private func extractNumber(from string: String) -> Int? {
        let components = string.components(separatedBy: CharacterSet.decimalDigits.inverted)
        return components.compactMap { Int($0) }.first
    }
}