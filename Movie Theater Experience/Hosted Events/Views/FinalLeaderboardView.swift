import SwiftUI
import Foundation

public struct FinalLeaderboardView: View {
    public let scores: [(table: EventTable, score: Int)]
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Final Leaderboard")
                .font(.title2.bold())
                .padding(.horizontal)
            
            List {
                ForEach(Array(scores.enumerated()), id: \.1.table.id) { index, entry in
                    HStack {
                        HStack(spacing: 8) {
                            Text("\(index + 1).")
                                .bold()
                            Text(entry.table.teamName ?? "Table \(entry.table.tableNumber)")
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer()
                        Text("\(entry.score) pts")
                            .monospacedDigit()
                            .bold()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

#if DEBUG
import simd

struct FinalLeaderboardView_Previews: PreviewProvider {
    static let sampleScores: [(table: EventTable, score: Int)] = [
        (table: EventTable(
            tableNumber: 1,
            tableName: nil,
            participants: [],
            maxSeats: 6,
            currentScore: 0,
            teamName: "Alpha Team",
            tablePosition: SIMD3<Float>(0, 0, 0),
            seatPositions: []
        ), score: 120),
        (table: EventTable(
            tableNumber: 2,
            tableName: nil,
            participants: [],
            maxSeats: 6,
            currentScore: 0,
            teamName: nil,
            tablePosition: SIMD3<Float>(1, 0, 0),
            seatPositions: []
        ), score: 110),
        (table: EventTable(
            tableNumber: 3,
            tableName: nil,
            participants: [],
            maxSeats: 6,
            currentScore: 0,
            teamName: "Bravo",
            tablePosition: SIMD3<Float>(2, 0, 0),
            seatPositions: []
        ), score: 100),
        (table: EventTable(
            tableNumber: 4,
            tableName: nil,
            participants: [],
            maxSeats: 6,
            currentScore: 0,
            teamName: nil,
            tablePosition: SIMD3<Float>(3, 0, 0),
            seatPositions: []
        ), score: 90)
    ]
    
    static var previews: some View {
        FinalLeaderboardView(scores: sampleScores)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
