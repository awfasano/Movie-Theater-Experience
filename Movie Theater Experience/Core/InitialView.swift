import SwiftUI
import RealityKit

struct InitialView: View {
    var body: some View {
        ZStack {
            // 3D background
            RealityView { content in
                // Create a container for our 3D objects
                let container = Entity()

                // Create a few spheres with different properties
                for _ in 0..<10 {
                    let sphere = ModelEntity(
                        mesh: .generateSphere(radius: Float.random(in: 0.1...0.3)),
                        materials: [SimpleMaterial(color: .white.withAlphaComponent(0.5), roughness: 0.3, isMetallic: true)]
                    )
                    sphere.position = SIMD3<Float>(
                        x: Float.random(in: -2...2),
                        y: Float.random(in: -2...2),
                        z: Float.random(in: -2...2)
                    )
                    container.addChild(sphere)

                    // Add a simple animation to each sphere.
                    let animation = FromToByAnimation<Transform>(
                        from: Transform(scale: .one, rotation: simd_quatf(angle: 0, axis: [0,1,0]), translation: sphere.position),
                        to: Transform(scale: .one, rotation: simd_quatf(angle: .pi * 2, axis: [Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1)]), translation: sphere.position),
                        duration: TimeInterval.random(in: 10...20),
                        timing: .linear
                    )
                    
                    // Generate a reusable animation resource from the definition.
                    let animationResource = try! AnimationResource.generate(with: animation)
                    
                    // Play the animation on the sphere and set it to loop.
                    sphere.playAnimation(animationResource)
                }
                content.add(container)
            }

            // Dark overlay for text readability
            Color.black.opacity(0.6)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Text("Step into a New Reality")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)


                Text("Your private virtual space for movies, music, and friends. Chat, react, and share moments in a world that's yours to command.")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Button(action: {
                    // Action to dismiss this view and show the main content
                }) {
                    Text("Enter the Theater")
                        .font(.headline)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                }
                .padding(.bottom, 50)
            }
            .padding()
        }
    }
}

struct InitialView_Previews: PreviewProvider {
    static var previews: some View {
        InitialView()
    }
}
