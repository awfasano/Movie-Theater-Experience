import Foundation

struct SpaceDetailViewModel {
    let space: SpaceData
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    var formattedLastModified: String {
        Self.dateFormatter.string(from: space.lastModified)
    }
    
    var tags: [String] {
        space.tags ?? []
    }
    
    var hasTags: Bool {
        !tags.isEmpty
    }
    
    var originalSceneURL: URL? {
        URL(string: space.usdzURL)
    }
}
