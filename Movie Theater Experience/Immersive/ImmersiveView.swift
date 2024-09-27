import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation

struct ImmersiveView: View {
    @Environment(\.openWindow) var openWindow
    @ObservedObject var sharedSelection = SharedSeatSelection.shared
    @ObservedObject var theatreEntityWrapper = TheatreEntityWrapper.shared


    var body: some View {
        VStack {
            // RealityKit Content View for visionOS
            RealityView { content in
                if let theatreEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                    // Set the theater entity in the wrapper for access in the seat map
                    self.theatreEntityWrapper.entity = theatreEntity

                    // Move the theater entity to align the desired point with the user's position
                    theatreEntity.transform.translation = SIMD3<Float>(0.45, -0.73, 0.126)

                    content.add(theatreEntity)

                    // Configure the screen entity for video playback
                    if let screenEntity = theatreEntity.findEntity(named: "polySurface11205_lambert184_0") as? ModelEntity {
                        configureScreenEntity(screenEntity)
                    }
                }
            }
        }
        .onChange(of: sharedSelection.selectedSeatEntity) { oldSelection, newSelection in
            guard let newSelection = newSelection,
                  let theatreEntity = theatreEntityWrapper.entity else {
                print("No seat or theatre entity found!")
                return
            }

            // Desired position of the seat relative to the user
            let desiredSeatPosition = SIMD3<Float>(0, 0, 0)

            // Get the seat's position in world coordinates
            let seatWorldPosition = newSelection.position(relativeTo: nil)

            // Calculate the offset needed to move the theater so the seat is at the desired position
            let offset = desiredSeatPosition - seatWorldPosition

            // Adjust the theater's translation
            theatreEntity.transform.translation += offset

            // Debugging
            print("Theatre entity moved to position: \(theatreEntity.transform.translation)")
            let newSeatWorldPosition = newSelection.position(relativeTo: nil)
            print("Seat's new world position: \(newSeatWorldPosition)")
        }
    }

    // Function to configure the screen entity for video playback
    func configureScreenEntity(_ screenEntity: ModelEntity) {
        if let videoURL = Bundle.main.url(forResource: "spiderman", withExtension: "mp4") {
            let asset = AVURLAsset(url: videoURL)
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)

            // Set the video as the material for the screen entity
            let videoMaterial = VideoMaterial(avPlayer: player)
            screenEntity.model?.materials = [videoMaterial]

            // Start video playback
            player.play()
            player.volume = 0

            // Adjust the screen's scale and rotation as needed
            screenEntity.scale = SIMD3<Float>(0.5, 1, 1)
            screenEntity.transform.rotation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 0, 1))
        }
    }

    // Function to simulate user movement by moving the theater entity
    func moveUser(by offset: SIMD3<Float>) {
        guard let theatreEntity = theatreEntityWrapper.entity else { return }

        // Move the theater entity in the opposite direction
        theatreEntity.transform.translation -= offset

        // Debugging
        print("Theater moved to position: \(theatreEntity.transform.translation)")
    }
}
