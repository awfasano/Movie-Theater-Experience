import SwiftUI
import RealityKit


struct SceneVolumeWindow: View {
    @State private var selectedSpaceId: Int? = nil
    @State private var spaces: [IntroSpace] = [
        IntroSpace(id: 1, name: "Main Theater", lastModified: Date(), currentOccupancy: 45, maxOccupancy: 100),
        IntroSpace(id: 2, name: "VIP Lounge", lastModified: Date(), currentOccupancy: 12, maxOccupancy: 30),
        IntroSpace(id: 3, name: "Concession Area", lastModified: Date(), currentOccupancy: 25, maxOccupancy: 50),
        IntroSpace(id: 4, name: "Entrance Hall", lastModified: Date(), currentOccupancy: 15, maxOccupancy: 40),
        IntroSpace(id: 5, name: "Private Screen", lastModified: Date(), currentOccupancy: 8, maxOccupancy: 20)
    ]

    var body: some View {
        HStack(spacing: 0) {
            // List sidebar
            NavigationStack {
                List(spaces, selection: $selectedSpaceId) { space in
                    SpaceRowView(space: space, isSelected: selectedSpaceId == space.id)
                        .padding(.vertical, 8)
                }
                .navigationTitle("Theater Spaces")
                .toolbar(id: "spaceTools") {
                    ToolbarItem(id: "addSpace", placement: .automatic) {
                        Button(action: {}) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .frame(width: 300)
            
            // 3D Volume preview with occupancy overlay
            ZStack {
                RealityView { content in
                    setupInitialContent(content)
                } update: { content in
                    if let selectedSpace = spaces.first(where: { $0.id == selectedSpaceId }) {
                        updateContent(content, with: selectedSpace)
                    } else {
                        resetContent(content)
                    }
                }
                .gesture(
                    DragGesture()
                        .targetedToAnyEntity()
                )
                
                // Occupancy overlay
                if let selectedSpace = spaces.first(where: { $0.id == selectedSpaceId }) {
                    VStack {
                        HStack {
                            Spacer()
                            OccupancyView(space: selectedSpace)
                                .padding()
                        }
                        Spacer()
                    }
                }
            }
        }
        .navigationSplitViewStyle(.automatic)
        .frame(width: 800, height: 600)
    }
    
    private func setupInitialContent(_ content: RealityViewContent) {
        // Create main theater model
        let theater = ModelEntity(
            mesh: .generateBox(size: [0.3, 0.2, 0.3]),
            materials: [SimpleMaterial(color: .blue, roughness: 0.3, isMetallic: true)]
        )
        theater.name = "theater"
        
        // Position the theater in front of the camera
        theater.position = [0, 0, -0.5]
        
        // Add floating number display
        let textMesh = MeshResource.generateText(
            "0",
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.05),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let textMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let occupancyText = ModelEntity(mesh: textMesh, materials: [textMaterial])
        occupancyText.name = "occupancyText"
        occupancyText.position = [0, 0.15, 0]
        theater.addChild(occupancyText)
        
        // Create spotlight
        let spotlight = SpotLight()
        spotlight.light.intensity = 800
        spotlight.light.innerAngleInDegrees = 45
        spotlight.light.outerAngleInDegrees = 60
        spotlight.light.attenuationRadius = 0.5
        spotlight.shadow = SpotLightComponent.Shadow()
        spotlight.name = "spotlight"
        spotlight.position = [0.3, 0.4, 0]
        spotlight.look(at: theater.position, from: spotlight.position, relativeTo: nil)
        
        // Create and configure the main anchor using a world anchor
        let mainAnchor = AnchorEntity(world: .zero)
        mainAnchor.position = [0, 0, -0.5]
        mainAnchor.addChild(theater)
        mainAnchor.addChild(spotlight)
        content.add(mainAnchor)
        
        // Add ambient lighting
        let ambient = DirectionalLight()
        ambient.light.intensity = 500
        let ambientAnchor = AnchorEntity(world: .zero)
        ambientAnchor.addChild(ambient)
        content.add(ambientAnchor)
    }

    
    private func updateContent(_ content: RealityViewContent, with space: IntroSpace) {
        guard let theater = content.entities.first(where: { $0.name == "theater" }) as? ModelEntity,
              let textEntity = theater.children.first(where: { $0.name == "occupancyText" }) as? ModelEntity,
              let spotlight = content.entities.first(where: { $0.name == "spotlight" }) as? SpotLight else { return }
        
        // Update occupancy text
        let updatedMesh = MeshResource.generateText(
            "\(space.currentOccupancy)",
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.05),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        textEntity.model?.mesh = updatedMesh
        
        // Create animations
        var rotateAnimation = theater.transform
        rotateAnimation.rotation = simd_quatf(angle: 2 * .pi, axis: [0, 1, 0])
        
        var scaleUp = theater.transform
        scaleUp.scale = [1.2, 1.2, 1.2]
        
        var moveUp = theater.transform
        moveUp.translation += [0, 0.05, 0]
        
        // Apply animations with timing
        theater.move(to: moveUp, relativeTo: theater, duration: 0.5, timingFunction: .easeInOut)
        theater.move(to: scaleUp, relativeTo: theater, duration: 0.7, timingFunction: .easeInOut)
        theater.move(to: rotateAnimation, relativeTo: theater, duration: 1.5, timingFunction: .easeInOut)
        
        // Update spotlight color based on occupancy
        let occupancyColor: UIColor
        switch space.occupancyPercentage {
        case ..<0.5: occupancyColor = .systemGreen
        case ..<0.8: occupancyColor = .systemYellow
        default: occupancyColor = .systemRed
        }
        spotlight.light.color = occupancyColor
        
        // Animate spotlight position
        var spotlightTransform = spotlight.transform
        spotlightTransform.rotation = simd_quatf(angle: .pi / 8, axis: [0, 1, 0])
        spotlight.move(to: spotlightTransform, relativeTo: spotlight, duration: 1.0, timingFunction: .easeInOut)
    }
    
    private func resetContent(_ content: RealityViewContent) {
        guard let theater = content.entities.first(where: { $0.name == "theater" }) as? ModelEntity,
              let spotlight = content.entities.first(where: { $0.name == "spotlight" }) as? SpotLight else { return }
        
        // Reset transform
        var resetTransform = theater.transform
        resetTransform.scale = [1, 1, 1]
        resetTransform.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        resetTransform.translation = [0, 0, 0]
        
        // Apply reset animation
        theater.move(to: resetTransform, relativeTo: theater, duration: 0.5, timingFunction: .easeInOut)
        
        // Reset spotlight
        spotlight.light.color = .white
    }
}

