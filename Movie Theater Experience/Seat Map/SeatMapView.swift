import SwiftUI
import RealityKit

@available(visionOS 1.0, *)
struct SeatMapView: View {
    @ObservedObject var sharedSelection = SharedSeatSelection.shared
    @ObservedObject var theatreEntityWrapper = TheatreEntityWrapper.shared
    @Environment(\.dismissWindow) private var dismissWindow
    
    @StateObject private var viewModel = SeatMapViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
        .task {
            await viewModel.loadSeats(theatreEntityWrapper: theatreEntityWrapper)
        }
    }
    
    private var header: some View {
        HStack {
            Text("Theatre Map")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal)
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
        ProgressView("Loading seats...")
            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundStyle)
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
        .background(backgroundStyle)
    }
    
    private var seatMapContent: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(viewModel.organizedRows) { row in
                    HStack {
                        // Row label with larger text
                        Text("Row \(row.rowNumber)")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundColor(.gray)
                            .frame(width: 120, alignment: .leading)
                            .padding(.leading)
                        
                        // Center the seats
                        HStack(spacing: SeatGeometry.spacing) {
                            ForEach(row.seats) { seat in
                                SeatButton(
                                    rowNumber: row.rowNumber,
                                    seatNumber: seat.seatNumber,
                                    isSelected: sharedSelection.currentRow == row.rowNumber && sharedSelection.currentSeat == seat.seatNumber,
                                    onSelect: { selectSeat(row: row.rowNumber, seat: seat.seatNumber, entity: seat.entity) }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Balance the spacing
                        Spacer()
                            .frame(width: 120)
                    }
                    .frame(maxWidth: .infinity)
                    .id(row.id)
                }
            }
            .padding()
        }
        .background(backgroundStyle)
    }
    
    private var backgroundStyle: some View {
        Color(UIColor.systemGroupedBackground)
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            .padding()
    }
    
    private func selectSeat(row: Int, seat: Int, entity: Entity) {
        withAnimation(.easeOut(duration: 0.2)) {
            sharedSelection.selectedSeatEntity = entity
            sharedSelection.currentRow = row
            sharedSelection.currentSeat = seat
        }
    }
}

// MARK: - ViewModel
@MainActor
class SeatMapViewModel: ObservableObject {
    @Published private(set) var organizedRows: [TheaterRow] = []
    @Published private(set) var isLoading = true
    
    func loadSeats(theatreEntityWrapper: TheatreEntityWrapper) async {
        guard let seatsEntity = findSeatsEntity(in: theatreEntityWrapper) else {
            isLoading = false
            return
        }
        
        // Move heavy processing to background
        let rows = await Task.detached(priority: .userInitiated) { [weak self] in
            await self?.organizeSeats(from: seatsEntity) ?? []
        }.value
        
        // Sort rows once during load
        organizedRows = rows.sorted(by: { $0.rowNumber < $1.rowNumber })
        isLoading = false
    }
    
    private func findSeatsEntity(in wrapper: TheatreEntityWrapper) -> Entity? {
        guard let rootEntity = wrapper.entity,
              let innerRoot = rootEntity.children.first(where: { $0.name == "Root" }) else {
            return nil
        }
        return innerRoot.children.first(where: { $0.name == "seats" })
    }
    
    private func organizeSeats(from seatsEntity: Entity) async -> [TheaterRow] {
        let rowEntities = seatsEntity.children
            .filter { $0.name.starts(with: "row_") }
        
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
            
            guard !seats.isEmpty else { return nil }
            
            return TheaterRow(
                id: "row_\(rowNumber)",
                entity: rowEntity,
                rowNumber: rowNumber,
                seats: seats.sorted(by: { $0.seatNumber < $1.seatNumber })
            )
        }
    }
    
    private func extractNumber(from string: String) -> Int? {
        string.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
            .first
    }
}
