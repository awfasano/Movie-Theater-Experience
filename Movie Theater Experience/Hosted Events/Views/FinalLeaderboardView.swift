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
struct FinalLeaderboardView_Previews: PreviewProvider {
    struct EventTable: Identifiable {
        let id: UUID
        let tableNumber: Int
        let teamName: String?
    }
    
    static let sampleScores: [(table: EventTable, score: Int)] = [
        (table: .init(id: UUID(), tableNumber: 1, teamName: "Alpha Team"), score: 120),
        (table: .init(id: UUID(), tableNumber: 2, teamName: nil), score: 110),
        (table: .init(id: UUID(), tableNumber: 3, teamName: "Bravo"), score: 100),
        (table: .init(id: UUID(), tableNumber: 4, teamName: nil), score: 90)
    ]
    
    static var previews: some View {
        FinalLeaderboardView(scores: sampleScores)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
