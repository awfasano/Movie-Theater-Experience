import SwiftUI

struct SpaceCardOccupancy {
    let displayText: String
    let color: Color
    
    static func make(from percentage: Float, userCount: Int) -> SpaceCardOccupancy {
        let display = "\(userCount) users"
        let color: Color
        switch percentage {
        case ..<0.5:
            color = .green
        case ..<0.8:
            color = .yellow
        default:
            color = .red
        }
        return SpaceCardOccupancy(displayText: display, color: color)
    }
}

struct SpaceCardViewModel {
    let space: SpaceData
    
    var occupancy: SpaceCardOccupancy {
        SpaceCardOccupancy.make(from: space.occupancyPercentage, userCount: space.currentUserCount)
    }
    
    var thumbnailURL: URL? {
        guard let urlString = space.thumbnailURL else { return nil }
        return URL(string: urlString)
    }
}
