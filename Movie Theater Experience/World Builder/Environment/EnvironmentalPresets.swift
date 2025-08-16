// MARK: - Environment Presets (defaults)
enum EnvironmentPreset: String, Codable, CaseIterable {
    case defaultOutdoor = "outdoor"
    case defaultIndoor  = "indoor"

    var displayName: String {
        switch self {
        case .defaultOutdoor: return "Basic Outdoor"
        case .defaultIndoor:  return "Basic Room"
        }
    }
    var description: String {
        switch self {
        case .defaultOutdoor: return "A simple outdoor sky + ground plane."
        case .defaultIndoor:  return "A small enclosed room."
        }
    }
    var icon: String {
        switch self {
        case .defaultOutdoor: return "sun.max.fill"
        case .defaultIndoor:  return "square.fill"
        }
    }
}

// MARK: - Firestore Environment Model
struct EnvironmentData: Codable, Identifiable {
    let id: String
    let name: String
    let category: String          // e.g. "nature", "indoor"
    let description: String
    let skybox: SkyboxSettings
    let lighting: LightingSettings
    let ground: GroundSettings
    let audio: AudioSettings?
    let weather: WeatherSettings?
    let tags: [String]
    let isPremium: Bool           // true = paid
    
    // added optional thumbnail from Firestore
    let thumbnailUrl: String?
    
    // allow controls to decide if it’s an “Open World” vs “Enclosed” space
    var worldCategory: WorldCategory {
        let enclosed = ["indoor", "room", "interior"]
        return enclosed.contains(category.lowercased())
            ? .enclosed
            : .open
    }
    
    // if this environment *is actually one of your default presets*
    // Firestore can link via `presetType` so you can fallback:
    var simplePreset: EnvironmentPreset? {
        EnvironmentPreset(rawValue: category)
    }
}

enum WorldCategory: String, CaseIterable {
    case open     = "Open World"
    case enclosed = "Enclosed Space"
}
