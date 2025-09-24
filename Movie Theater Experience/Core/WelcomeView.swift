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
    @Environment(\.openWindow) private var openWindow

    
    // New state for light pulsing animation
    @State private var lightPulse = false

    var body: some View {
        ZStack {
            // --- Enhanced Animated Aurora Background with Additional Light ---
            ZStack {
                // Existing aurora circles
                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 500)
                    .blur(radius: 150)
                    .offset(x: animateCircle1 ? 250 : -250, y: animateCircle1 ? -150 : 150)
                
                Circle()
                    .fill(Color.purple.opacity(0.5))
                    .frame(width: 600)
                    .blur(radius: 180)
                    .offset(x: animateCircle2 ? -300 : 300, y: animateCircle2 ? 200 : -200)
                
                Circle()
                    .fill(Color.cyan.opacity(0.4))
                    .frame(width: 450)
                    .blur(radius: 130)
                    .offset(x: animateCircle3 ? 150 : -150, y: animateCircle3 ? 250 : -250)
                
                // NEW: Central light source with pulsing animation
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(lightPulse ? 0.8 : 0.4),
                            Color.yellow.opacity(lightPulse ? 0.6 : 0.3),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: lightPulse ? 400 : 300
                    ))
                    .frame(width: 800, height: 800)
                    .blur(radius: 100)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: lightPulse)
                
                // NEW: Additional ambient light overlay
                Rectangle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.1),
                            Color.clear,
                            Color.white.opacity(0.05)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .ignoresSafeArea()
            }

            // --- Main Content VStack ---
            VStack(spacing: 20) {
                // 1. Enhanced 3D Scene with lighting
                RealityView { content in
                    async let introScene = Entity(named: "intro", in: realityKitContentBundle)
                    async let emitter = Entity(named: "projectorEmitter", in: realityKitContentBundle)
                    
                    if let scene = try? await introScene {
                        scene.scale = [0.1, 0.1, 0.1]
                        scene.transform.translation.y += -0.075
                        content.add(scene)
                    }
                    if let particles = try? await emitter {
                        particles.scale = [0.5, 0.05, 0.15]
                        content.add(particles)
                    }
                    
                    // NEW: Add directional light to the 3D scene
                    let directionalLight = DirectionalLight()
                    directionalLight.light.intensity = 2000
                    directionalLight.light.color = .white
                    directionalLight.orientation = simd_quatf(angle: .pi/4, axis: [0, 1, 0])
                    content.add(directionalLight)
                    
                    // NEW: Add point light for additional brightness
                    let pointLight = PointLight()
                    pointLight.light.intensity = 1500
                    pointLight.light.color = .white
                    pointLight.position = [0, 0.2, 0.5]
                    content.add(pointLight)
                    
                    // NEW: Add another point light from different angle
                    let fillLight = PointLight()
                    fillLight.light.intensity = 800
                    fillLight.light.color = UIColor(red: 1.0, green: 0.95, blue: 0.8, alpha: 1.0)
                    fillLight.position = [-0.3, 0.1, 0.3]
                    content.add(fillLight)
                    
                } placeholder: {
                    ProgressView().frame(height: 300)
                }
                .frame(width: 300, height: 300)
                .rotation3DEffect(.degrees(showContent ? 30 : -30), axis: (x: 0, y: 1, z: 0))
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: showContent)
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.8)
                // NEW: Add a subtle glow around the 3D scene
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 350, height: 350)
                        .blur(radius: 50)
                )

                // 2. Enhanced text with better contrast
                VStack {
                    Text("Welcome to Spiera")
                        .font(.extraLargeTitle2).fontWeight(.bold)
                        .foregroundColor(.primary) // Ensures good contrast
                    
                    Text("Discover immersive 3D spaces, each filled with unique stories, music, and interactive content. We're just getting started—new worlds and features will be added regularly.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 500)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                // NEW: Add subtle text shadow for better readability
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                
                // 3. Enhanced call to action button
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
                // NEW: Add button glow effect
                .shadow(color: .accentColor.opacity(0.5), radius: 10, x: 0, y: 5)
                
                #if DEBUG
                FirebaseDebugButton()
                #endif
                                
            }
            .padding(40)
        }
        .onAppear {
            // Trigger animations
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 1)) {
                showContent = true
            }
            
            // NEW: Start light pulsing animation
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                lightPulse = true
            }
            
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
