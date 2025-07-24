import SwiftUI
import RealityKit
import RealityKitContent

struct WelcomeView: View {
    // This binding allows this view to change the active tab in the parent TabView.
    @Binding var selectedTab: Int
    
    // State for the main content animation
    @State private var showContent = false
    
    // State for animating each aurora background shape independently
    @State private var animateCircle1 = false
    @State private var animateCircle2 = false
    @State private var animateCircle3 = false

    var body: some View {
        ZStack {
            // --- START: Animated Aurora Background ---
            // A container to hold the blurred shapes
            ZStack {
                // Shape 1
                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 500)
                    .blur(radius: 150)
                    .offset(x: animateCircle1 ? 250 : -250, y: animateCircle1 ? -150 : 150)
                
                // Shape 2
                Circle()
                    .fill(Color.purple.opacity(0.5))
                    .frame(width: 600)
                    .blur(radius: 180)
                    .offset(x: animateCircle2 ? -300 : 300, y: animateCircle2 ? 200 : -200)
                
                // Shape 3
                Circle()
                    .fill(Color.cyan.opacity(0.4))
                    .frame(width: 450)
                    .blur(radius: 130)
                    .offset(x: animateCircle3 ? 150 : -150, y: animateCircle3 ? 250 : -250)
            }
            // A material layer on top to give it a frosted glass feel
            // --- END: Animated Aurora Background ---

            // Your main content VStack
            VStack(spacing: 20) {
                // 1. 3D Scene as the centerpiece
                RealityView { content in
                    // Concurrently load the intro scene and the projector emitter
                    async let introScene = Entity(named: "intro", in: realityKitContentBundle)
                    async let emitter = Entity(named: "projectorEmitter", in: realityKitContentBundle)
                    
                    // Add both to the content once they are loaded
                    if let scene = try? await introScene {
                        scene.scale = [0.1, 0.1, 0.1]
                        scene.transform.translation.y += -0.075
                        content.add(scene)
                    }
                    if let particles = try? await emitter {
                        particles.scale = [0.5, 0.05, 0.15]
                        content.add(particles)
                    }
                } placeholder: {
                    ProgressView().frame(height: 300)
                }
                .frame(width: 300, height: 300)
                .rotation3DEffect(.degrees(showContent ? 30 : -30), axis: (x: 0, y: 1, z: 0))
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: showContent)
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.8)

                // 2. Animated explanatory text
                VStack {
                    Text("Welcome to Spaces")
                        .font(.extraLargeTitle2).fontWeight(.bold)
                    
                    Text("Browse unique spaces, with stories, music, and more.  We have a lot more coming in VisionOS 26\n so stay tuned")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 500)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                
                // 3. Call to action button
                Button(action: {
                    withAnimation { selectedTab = 1 }
                }) {
                    Text("Browse Spaces")
                        .font(.title3).fontWeight(.semibold).padding(.horizontal, 20)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .hoverEffect(.lift)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
            }
            .padding(40)
        }
        .onAppear {
            // Trigger the animations when the view appears.
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 1)) {
                showContent = true
            }
            
            // Start the background gradient animations with staggered durations
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: true)) {
                animateCircle1.toggle()
            }
            
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: true)) {
                animateCircle2.toggle()
            }
            
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: true)) {
                animateCircle3.toggle()
            }
        }
    }
}
