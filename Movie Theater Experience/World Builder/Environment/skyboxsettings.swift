//
//  skyboxsettings.swift
//  Movie Theater Experience
//
//  Created by Anthony Fasano on 8/16/25.
//

import Foundation

// MARK: - Skybox Settings (FULL Procedural Support)

struct SkyboxSettings: Codable {
    let type: SkyboxType         // .hdri, .procedural, .simple, .hybrid
    let assetUrl: String?        // HDRI
    let thumbnailUrl: String?
    let proceduralSettings: ProceduralSkyboxSettings?
    
    enum SkyboxType: String, Codable {
        case hdri, procedural, simple, hybrid
    }
}

// -- Procedural
struct ProceduralSkyboxSettings: Codable {
    let skyGradient: SkyGradient?
    let sun: SunSettings?
    let clouds: CloudSettings?
    let atmosphere: AtmosphereSettings?
    let nightSky: NightSkySettings?
    let timeOfDayPresets: [String: TimeOfDayPreset]?
    let weatherEffects: [String: AnyCodable]? // <-- Generic fallback
}

// Gradient
struct SkyGradient: Codable {
    struct GradientStop: Codable {
        let position: Double
        let color: String
    }
    let gradientStops: [GradientStop]
    let interpolation: String?
    let seasonalTints: [String: SeasonalTint]?
    
    struct SeasonalTint: Codable {
        let hue: Float
        let saturation: Float
        let brightness: Float
    }
}

// Sun
struct SunSettings: Codable {
    let enabled: Bool
    let position: SunPosition
    let appearance: SunAppearance
    let volumetricLighting: VolumetricLighting?
    
    struct SunPosition: Codable {
        let azimuth: Float
        let elevation: Float
        let useDynamicPath: Bool?
        let timeOfDay: Float?
        let latitude: Float?
        let dayOfYear: Int?
    }
    struct SunAppearance: Codable {
        let diskSize: Float
        let color: String
        let intensity: Float
        let corona: Corona?
        let lensFlare: LensFlare?
        
        struct Corona: Codable {
            let enabled: Bool
            let size: Float
            let color: String
            let intensity: Float
            let falloff: Float
        }
        struct LensFlare: Codable {
            let enabled: Bool
            let intensity: Float
            let elements: [FlareElement]
            struct FlareElement: Codable {
                let size: Float
                let distance: Float
                let color: String
            }
        }
    }
}

struct VolumetricLighting: Codable {
    let enabled: Bool
    let intensity: Float
    let rays: RaySettings
    let particles: ParticleSettings?
    let canopyOcclusion: CanopyOcclusion?
    
    struct RaySettings: Codable {
        let count: Int
        let length: Float
        let width: Float
        let spread: Float
        let animation: RayAnimation?
        
        struct RayAnimation: Codable {
            let enabled: Bool
            let swaySpeed: Float
            let swayAmount: Float
            let intensityVariation: Float
            let intensitySpeed: Float
        }
    }
    struct ParticleSettings: Codable {
        let enabled: Bool
        let density: Float
        let size: Float
        let speed: Float
        let color: String
        let sparkle: Bool
    }
    struct CanopyOcclusion: Codable {
        let enabled: Bool
        let pattern: String
        let density: Float
        let leafMovement: Bool
        let movementSpeed: Float?
        let movementScale: Float?
    }
}

// Clouds
struct CloudSettings: Codable {
    let enabled: Bool
    let layers: [CloudLayer]
    let cloudShadows: CloudShadows?
    
    struct CloudLayer: Codable {
        let type: String
        let enabled: Bool
        let coverage: Float?
        let density: Float?
        let altitude: Float?
        let thickness: Float?
        let opacity: Float?
        let color: [String: String]? // flexible RGB dictionary
        let generation: [String: AnyCodable]? // algorithm, params, etc.
        let movement: [String: AnyCodable]?
        let slopeBased: Bool?        // optional from ground struct
    }
    struct CloudShadows: Codable {
        let enabled: Bool
        let intensity: Float
        let softness: Float
        let speed: Float
        let scale: Float
    }
}

// Atmosphere
struct AtmosphereSettings: Codable {
    let rayleigh: ScatteringSettings?
    let mie: ScatteringSettings?
    let ozone: OzoneSettings?
    let forestHaze: HazeSettings?
    
    struct ScatteringSettings: Codable {
        let intensity: Float
        let scaleHeight: Float
    }
    struct OzoneSettings: Codable {
        let enabled: Bool
        let intensity: Float
        let layer: Float
    }
    struct HazeSettings: Codable {
        let enabled: Bool
        let density: Float
        let color: String
        let heightFalloff: Float
        let startDistance: Float
        let endDistance: Float
    }
}

// Night Sky
struct NightSkySettings: Codable {
    let stars: StarSettings?
    let moon: MoonSettings?
    let aurora: AuroraSettings?
    
    struct StarSettings: Codable {
        let enabled: Bool
        let density: Int
        let brightness: Float
        let twinkle: TwinkleSettings?
        let milkyWay: MilkyWaySettings?
        
        struct TwinkleSettings: Codable {
            let enabled: Bool
            let speed: Float
            let amount: Float
        }
        struct MilkyWaySettings: Codable {
            let enabled: Bool
            let intensity: Float
            let rotation: Float
        }
    }
    struct MoonSettings: Codable {
        let enabled: Bool
        let phase: Float
        let size: Float
        let position: MoonPosition
        
        struct MoonPosition: Codable {
            let azimuth: Float
            let elevation: Float
        }
    }
    struct AuroraSettings: Codable {
        let enabled: Bool
        let intensity: Float
        let colors: [String]
    }
}

// Time of Day snapshots
struct TimeOfDayPreset: Codable {
    let sun: SunPosition?
    let fogDensity: Float?
    let volumetricIntensity: Float?
    
    struct SunPosition: Codable {
        let elevation: Float
        let azimuth: Float
    }
}


// Drop this into a new file named AnyCodable.swift

import Foundation

struct AnyCodable: Codable {
    var value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) { value = intValue }
        else if let doubleValue = try? container.decode(Double.self) { value = doubleValue }
        else if let boolValue = try? container.decode(Bool.self) { value = boolValue }
        else if let stringValue = try? container.decode(String.self) { value = stringValue }
        else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        }
        else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        }
        else { value = () }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int: try container.encode(intValue)
        case let doubleValue as Double: try container.encode(doubleValue)
        case let boolValue as Bool: try container.encode(boolValue)
        case let stringValue as String: try container.encode(stringValue)
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        default:
            break
        }
    }
}
