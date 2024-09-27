import RealityKit
import AVFoundation
// Ensure you register this component in your app’s delegate using:
// VideoComponent.registerComponent()
struct VideoComponent: Component, Decodable {
    var avPlayer: AVPlayer?
    // ... other properties you need to encode/decode

    enum CodingKeys: CodingKey {
        case playbackTime // Example of a property to decode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decode the properties of your VideoComponent here
        let playbackTime = try container.decode(Double.self, forKey: .playbackTime)

        // Logic to recreate your component state, potentially reinitializing the AVPlayer
        // based on saved information like playbackTime
    }
}



