d# Integrating Painterly Materials into SpaceDrawingRenderer

## Overview

This guide shows the key changes needed to integrate the new painterly materials (Oil, Watercolor, Ink, Neon) into your existing `SpaceDrawingRenderer`.

## 1. Add Material Manager Property

At the top of `SpaceDrawingRenderer`, add:

```swift
#if os(visionOS)
private let materialManager = PainterlyMaterialManager.shared
#endif
```

## 2. Update `attach(to:)` Method

Ensure materials start loading when the renderer attaches:

```swift
func attach(to entity: Entity) {
    if rootAnchor !== entity {
        strokeContainer.removeFromParent()
        volumeGuide?.removeFromParent()
        entity.addChild(strokeContainer)
        rootAnchor = entity
    }
    ensureVolumeGuide()
    
    #if os(visionOS)
    // Start loading painterly materials
    materialManager.ensureLoaded()
    #endif
}
```

## 3. Update `buildStrokeEntity(for:)` Method

Replace the material selection logic:

```swift
private func buildStrokeEntity(for stroke: SpaceStroke) -> Entity? {
    guard let anchor = rootAnchor else { return nil }
    var points = stroke.points.map { anchor.convert(position: $0.simdVector, from: nil) }
    guard !points.isEmpty else { return nil }
    let radius = max(Float(stroke.width) * 0.5, 0.001)
    points = prepareStrokePoints(points, radius: radius, style: stroke.style)
    let lapIterations = stroke.style == .classicCylinder ? 1 : 2
    let lapFactor: Float = stroke.style == .classicCylinder ? 0.25 : 0.4
    points = laplacianSmooth(points, iterations: lapIterations, smoothingFactor: lapFactor)
    guard let first = points.first else { return nil }
    
    // Get the appropriate material
    let strokeMaterial: any Material = getMaterial(for: stroke)
    let rgba = stroke.color.rgbaComponents
    let strokeVertexColor = SIMD4<Float>(Float(rgba.r), Float(rgba.g), Float(rgba.b), Float(rgba.a))

    if points.count == 1 {
        return makeSinglePointEntity(
            style: stroke.style,
            point: first,
            radius: radius,
            material: strokeMaterial,
            anchor: anchor,
            strokeId: stroke.strokeId
        )
    }
    
    // Route to appropriate geometry based on style
    switch stroke.style {
    case .tubular, .classicCylinder:
        return buildTubeEntity(points: points, radius: radius, stroke: stroke, material: strokeMaterial)
        
    case .flat, .ribbon, .oil, .watercolor, .ink:
        // All these use ribbon geometry
        return buildRibbonEntity(points: points, radius: radius, stroke: stroke, 
                                  strokeColor: strokeVertexColor, material: strokeMaterial)
        
    case .neon:
        // Neon uses tube geometry with emissive material
        return buildTubeEntity(points: points, radius: radius, stroke: stroke, material: strokeMaterial)
        
    case .box:
        return buildBoxEntity(points: points, radius: radius, stroke: stroke, material: strokeMaterial)
    }
}

private func getMaterial(for stroke: SpaceStroke) -> any Material {
    #if os(visionOS)
    // Check for painterly material first
    if let painterlyMaterial = materialManager.material(for: stroke.style) {
        return materialManager.configuredMaterial(base: painterlyMaterial, for: stroke)
    }
    #endif
    
    // Fall back to PBR material
    return material(for: stroke)
}
```

## 4. Update Ribbon Mesh Generation for Vertex Colors

The ribbon mesh needs to include vertex colors that the shader can read. Update `makeRibbonMesh`:

```swift
private func makeRibbonMesh(
    points: [SIMD3<Float>],
    baseRadius: Float,
    strokeId: String,
    strokeColor: SIMD4<Float>,
    normal: SIMD3<Float>
) -> MeshResource? {
    guard points.count >= 2 else { return nil }
    
    var descriptor = MeshDescriptor()
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var texCoords: [SIMD2<Float>] = []
    var colors: [SIMD4<Float>] = []  // ADD THIS
    
    let vFractions = arcLengthFractions(points)
    let frames = computeBishopFrames(points: points, referenceNormal: normal)
    
    for (index, point) in points.enumerated() {
        // ... existing frame calculation code ...
        
        // ADD: Store vertex colors
        colors.append(strokeColor)
        colors.append(strokeColor)
    }
    
    // ... existing index generation ...
    
    descriptor.positions = MeshBuffer(positions)
    descriptor.normals = MeshBuffer(normals)
    descriptor.textureCoordinates = MeshBuffer(texCoords)
    descriptor.colors = MeshBuffer(colors)  // ADD THIS - maps to "displayColor" geomprop
    descriptor.primitives = .triangles(indices)
    
    return try? MeshResource.generate(from: [descriptor])
}
```

## 5. File Locations

Place the USDA files in your RealityKit content package:

```
Packages/RealityKitContent/Sources/RealityKitContent/
└── RealityKitContent.rkassets/
    └── Materials/
        ├── OilBrush.usda
        ├── WatercolorBrush.usda
        ├── InkBrush.usda
        ├── NeonBrush.usda
        └── BrushTextures/
            ├── oil_stroke_1.png
            ├── brush_fiber_noise.png
            └── brush_streaks.png
```

## 6. Texture Requirements

The shaders reference these textures. Create or source them:

| Texture | Purpose | Format |
|---------|---------|--------|
| `oil_stroke_1.png` | Stroke alpha mask | Grayscale PNG, ~256x256 |
| `brush_fiber_noise.png` | Organic variation | Grayscale PNG, tileable, ~128x128 |
| `brush_streaks.png` | Bristle marks | Grayscale PNG, tall aspect ratio, ~64x256 |

### Creating Placeholder Textures

If you don't have textures yet, create simple placeholders:

```swift
// Generate a simple gradient mask in code
func createStrokeMaskTexture() -> CGImage {
    let size = CGSize(width: 256, height: 64)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { ctx in
        // Soft edge gradient across width
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceGray(),
            colors: [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.black.cgColor] as CFArray,
            locations: [0, 0.7, 1.0]
        )!
        ctx.cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: size.width/2, y: 0),
            end: CGPoint(x: size.width, y: 0),
            options: []
        )
    }
    return image.cgImage!
}
```

## 7. Testing the Integration

1. Build and run on visionOS Simulator or device
2. Check console for material loading messages:
   ```
   🎨 PainterlyMaterialManager: Loaded 4/4 materials
   ```
3. Select a painterly brush (Oil, Watercolor, Ink, Neon)
4. Draw a stroke and verify the shader effect is visible

## Common Issues

### Materials Not Loading
- Verify USDA files are in the correct location
- Check that RealityKitContent package is properly linked
- Look for "Failed to load" errors in console

### Vertex Colors Not Showing
- Ensure `descriptor.colors = MeshBuffer(colors)` is set
- Verify shader uses `ND_geompropvalue_color3` with `inputs:geomprop = "displayColor"`

### Textures Not Found
- Verify texture files exist in `BrushTextures/` folder
- Check file paths in USDA match actual filenames
- Ensure textures are included in the build target

### Strokes Appear Black
- The shader might be failing silently
- Add fallback: if painterly material is nil, use PBR material
