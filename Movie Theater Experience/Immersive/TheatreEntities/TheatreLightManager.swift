import SwiftUI
import RealityKit
import RealityKitContent

@available(visionOS 2.0, *)
@MainActor
class TheatreLightingManager: ObservableObject {
    // MARK: - Properties
    @Published private(set) var projectorLight: Entity?
    private weak var volumetricBeam: ModelEntity?
    private var dustEmitter: ParticleEmitterComponent?
    private var isConfigured: Bool = false
    private weak var flickerTimer: Timer?
    private var baseOpacity: PhysicallyBasedMaterial.Opacity = .init(floatLiteral: 0.03)
    
    // MARK: - Beam Configuration
    private let beamColor = UIColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 0.05)
    private let lightIntensity: Float = 5
    private let beamLength: Float = 5.0
    private let beamWidth: Float = 0.5
    private let beamHeight: Float = 0.5
    
    // MARK: - Flicker Configuration
    private let flickerMinOpacity: Double = 0.08
    private let flickerMaxOpacity: Double = 0.15
    private let flickerMinInterval: TimeInterval = 0.07
    private let flickerMaxInterval: TimeInterval = 0.22
    
    // MARK: - Dust Configuration
    private let dustParticleSize: Float = 0.03
    private let dustEmissionRate: Float = 10
    private let dustLifespan: Float = 25.0
    private let dustDriftSpeed: Float = 0.1
    
    // MARK: - Public Methods
    func configureLighting(theatreEntity: Entity) async {
        // Stop any existing effects first
        await stopMovieLightingEffect()
        
        print("🎬 Configuring cinematic projection lighting...")
        ensureTheatreVisibility(theatreEntity)
        
        if let cameraEntity = findEntity(byName: "Vintage_Movie_Camera", in: theatreEntity) {
            print("Found camera entity")
            
            if let lightEntity = findEntity(byName: "DirectionalLight_camera", in: cameraEntity) {
                print("Found light entity in camera")
                setupProjectorLight(at: lightEntity)
                isConfigured = true
                self.projectorLight = lightEntity
                await startFlickerEffect()
            } else {
                print("Creating new light entity")
                let newLight = Entity()
                newLight.name = "DirectionalLight_camera"
                cameraEntity.addChild(newLight)
                setupProjectorLight(at: newLight)
                isConfigured = true
                self.projectorLight = newLight
                await startFlickerEffect()
            }
        } else {
            print("❌ Failed to find Vintage_Movie_Camera entity")
        }
    }
    
    func startMovieLightingEffect() async {
        if !isConfigured {
            print("⚠️ Warning: Lighting system not configured")
            return
        }
        if var emitter = dustEmitter {
            emitter.mainEmitter.birthRate = dustEmissionRate
        }
        await startFlickerEffect()
    }
    
    func stopMovieLightingEffect() async {
        await stopFlickerEffect()
        if var emitter = dustEmitter {
            emitter.mainEmitter.birthRate = 0
        }
        // Clear references
        volumetricBeam = nil
        dustEmitter = nil
    }
    
    // MARK: - Private Methods - Flicker Effect
    private func startFlickerEffect() async {
        await stopFlickerEffect()
        
        guard let volumetricBeam = volumetricBeam else { return }
        
        flickerTimer = Timer.scheduledTimer(withTimeInterval: flickerMinInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let randomOpacityValue = Double.random(in: self.flickerMinOpacity...self.flickerMaxOpacity)
            let randomOpacity = PhysicallyBasedMaterial.Opacity(floatLiteral: Float(randomOpacityValue))
            let nextInterval = Double.random(in: self.flickerMinInterval...self.flickerMaxInterval)
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let material = volumetricBeam.model?.materials.first as? UnlitMaterial {
                    var updatedMaterial = material
                    updatedMaterial.blending = .transparent(opacity: randomOpacity)
                    volumetricBeam.model?.materials = [updatedMaterial]
                }
            }
            
            self.flickerTimer?.invalidate()
            self.flickerTimer = Timer.scheduledTimer(withTimeInterval: nextInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.startFlickerEffect()
                }
            }
        }
    }
    
    private func stopFlickerEffect() async {
        flickerTimer?.invalidate()
        flickerTimer = nil
        
        if let volumetricBeam = volumetricBeam,
           let material = volumetricBeam.model?.materials.first as? UnlitMaterial {
            var updatedMaterial = material
            updatedMaterial.blending = .transparent(opacity: baseOpacity)
            volumetricBeam.model?.materials = [updatedMaterial]
        }
    }
    
    // MARK: - Private Methods - Dust Effect
    private func setupDustEmitter(at location: Entity) {
        typealias ParticleEmitter = ParticleEmitterComponent.ParticleEmitter
        typealias ParticleColor = ParticleEmitter.ParticleColor
        typealias ParticleColorValue = ParticleColor.ColorValue
        
        // Create particle system
        var emitterSettings = ParticleEmitterComponent()
        
        // Emission settings
        emitterSettings.mainEmitter.birthRate = dustEmissionRate
        emitterSettings.mainEmitter.lifeSpan = Double(dustLifespan)
        
        // Configure cone-shaped emission
        emitterSettings.emitterShape = .cone
        emitterSettings.mainEmitter.spreadingAngle = 60
        emitterSettings.mainEmitter.angle = 0
        
        // Emission volume
        emitterSettings.emitterShapeSize = SIMD3<Float>(
            beamLength * 0.18,
            beamWidth * 0.01,
            -beamHeight * 0.4
        )
        
        // Position
        let emitterPosition = SIMD3<Float>(0, 0, -beamLength * 0.15)
        
        // Particle behavior
        emitterSettings.speed = dustDriftSpeed * 0.07
        emitterSettings.mainEmitter.acceleration = SIMD3<Float>(
            dustDriftSpeed * 0.05,
            dustDriftSpeed * 0.05,
            dustDriftSpeed * 0.05
        )
        
        // Particle coloring
        let baseColor = Color(red: 1.0, green: 0.98, blue: 0.95, opacity: 0.3)
        let color1 = ParticleEmitter.Color(baseColor)
        let color2 = ParticleEmitter.Color(baseColor.opacity(0.15))
        let colorValue = ParticleColorValue.random(a: color1, b: color2)
        emitterSettings.mainEmitter.color = ParticleColor.constant(colorValue)
        
        // Particle fading and size
        emitterSettings.mainEmitter.opacityCurve = .linearFadeOut
        emitterSettings.mainEmitter.sizeVariation = dustParticleSize * 0.6
        
        // Create and configure particle entity
        let particleEntity = ModelEntity()
        particleEntity.components[ParticleEmitterComponent.self] = emitterSettings
        particleEntity.position = emitterPosition
        
        var material = UnlitMaterial(color: .white)
        material.writesDepth = false
        material.faceCulling = .none
        material.blending = .opaque
        particleEntity.model?.materials = [material]
        
        // Rotate particle system
        let horizontalBeamRotation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        let additionalRotation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        let combinedRotation = additionalRotation * horizontalBeamRotation
        particleEntity.orientation = combinedRotation
        
        location.addChild(particleEntity)
        dustEmitter = emitterSettings
    }
    
    // MARK: - Private Methods - Projector Light
    private func setupProjectorLight(at location: Entity) {
        print("Setting up projector light at position: \(location.position)")
        
        location.components[SpotLightComponent.self] = nil
        
        let vertices: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(beamLength, beamHeight * 0.5, -beamWidth),
            SIMD3<Float>(beamLength, beamHeight * 0.5, beamWidth),
            SIMD3<Float>(beamLength, -beamHeight, beamWidth),
            SIMD3<Float>(beamLength, -beamHeight, -beamWidth)
        ]
        
        let uvs: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0.5),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 0)
        ]
        
        let triangles: [UInt32] = [
            0, 1, 2,
            0, 2, 3,
            0, 3, 4,
            0, 4, 1,
            1, 4, 3,
            1, 3, 2,
            2, 1, 0,
            3, 2, 0,
            4, 3, 0,
            1, 4, 0,
            3, 4, 1,
            2, 3, 1
        ]
        
        var meshDescriptor = MeshDescriptor(name: "beam_from_point")
        meshDescriptor.positions = MeshBuffer(vertices)
        meshDescriptor.textureCoordinates = MeshBuffer(uvs)
        meshDescriptor.primitives = .triangles(triangles)
        
        let beamMesh = try! MeshResource.generate(from: [meshDescriptor])
        var material = UnlitMaterial()
        material.faceCulling = .none
        
        if let gradientTexture = generateGradientTexture(length: beamLength)?.cgImage {
            do {
                let texture = try TextureResource.generate(from: gradientTexture, options: .init(semantic: .color))
                material.color = .init(texture: .init(texture))
            } catch {
                print("⚠️ Failed to generate RealityKit texture. Using fallback color.")
                material.color = .init(tint: UIColor.white)
            }
        } else {
            print("⚠️ Failed to generate gradient UIImage. Using fallback color.")
            material.color = .init(tint: UIColor.white)
        }
        
        material.blending = .transparent(opacity: baseOpacity)
        
        let beam = ModelEntity(mesh: beamMesh, materials: [material])
        beam.isEnabled = true
        
        let horizontalBeamRotation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        let additionalRotation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        let combinedRotation = additionalRotation * horizontalBeamRotation
        
        beam.orientation = combinedRotation
        beam.position = SIMD3<Float>(0, 0, 0)
        
        location.addChild(beam)
        volumetricBeam = beam
        
        setupDustEmitter(at: location)
    }
    
    // MARK: - Private Methods - Utilities
    private func generateGradientTexture(length: Float) -> UIImage? {
        let size = CGSize(width: 256, height: 1)
        UIGraphicsBeginImageContext(size)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        let colors = [UIColor.white.cgColor, UIColor.clear.cgColor]
        let locations: [CGFloat] = [0.0, 0.4]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: colors as CFArray,
                                locations: locations)!
        
        context.drawLinearGradient(gradient,
                                 start: CGPoint(x: 0, y: 0),
                                 end: CGPoint(x: size.width, y: 0),
                                 options: [])
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
    
    private func ensureTheatreVisibility(_ theatreEntity: Entity) {
        theatreEntity.isEnabled = true
        for child in theatreEntity.children {
            child.isEnabled = true
        }
    }
    
    private func findEntity(byName name: String, in entity: Entity) -> Entity? {
        if entity.name == name {
            return entity
        }
        for child in entity.children {
            if let found = findEntity(byName: name, in: child) {
                return found
            }
        }
        return nil
    }
    
    // MARK: - Cleanup
    deinit {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.stopMovieLightingEffect()
            self.flickerTimer?.invalidate()
            self.flickerTimer = nil
        }
        print("TheatreLightingManager being deinitialized")
    }
}
