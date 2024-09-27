import SwiftUI
import RealityKit

struct SeatMapView: View {
    @ObservedObject var sharedSelection = SharedSeatSelection.shared
    @ObservedObject var theatreEntityWrapper = TheatreEntityWrapper.shared
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if let seatsEntity = theatreEntityWrapper.entity?.findEntity(named: "seats"),
           !seatsEntity.children.isEmpty {
            VStack {
                HStack {
                    Text("Theatre Map")
                        .font(.title)
                        .padding()
                    Spacer()
                    Button(action: {
                        print("we moved!")
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title)
                    }
                }
                ScrollView {
                    ForEach(0 ..< seatsEntity.children.count, id: \.self) { rowIndex in
                        let rowEntity = seatsEntity.children[rowIndex]
                        HStack {
                            ForEach(0 ..< rowEntity.children.count, id: \.self) { seatIndex in
                                let seatEntity = rowEntity.children[seatIndex]
                                Button(action: {
                                    // Update shared selection when a seat is selected
                                    sharedSelection.selectedSeatEntity = seatEntity
                                }) {
                                    Image(systemName: "chair.lounge.fill")
                                        .foregroundColor(.blue)
                                        .font(.title)
                                        .padding(.all, 5)
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        } else {
            // Handle case where seatsEntity or its children are missing
            VStack {
                Text("Seats not available")
                    .font(.title)
                    .foregroundColor(.red)
                    .padding()
                Button("Dismiss") {
                    dismissWindow()
                }
            }
        }
    }
}
