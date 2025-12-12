//
//  PainterlyMaterialManager.swift
//  Movie Theater Experience
//
//  Manages loading and caching of painterly ShaderGraphMaterials
//

import Foundation
import RealityKit
import RealityKitContent
import SwiftUI

#if os(visionOS)

/// Manages the loading and caching of painterly ShaderGraphMaterials.
/// Materials are loaded once and reused across all strokes.
@MainActor
final class PainterlyMaterialManager {
    
    static let shared = PainterlyMaterialManager()
    
    // MARK: - Material Cache
    
    private var oilMaterial: ShaderGraphMaterial?
    private var watercolorMaterial: ShaderGraphMaterial?
    private var inkMaterial: ShaderGraphMaterial?
    private var neonMaterial: ShaderGraphMaterial?
    
    private var loadTask: Task<Void, Never>?
    private var isLoaded = false
    
    // MARK: - Public Interface
    
    /// Returns the appropriate material for a stroke style, or nil if not a painterly style
    func material(for style: SpaceStroke.Style) -> ShaderGraphMaterial? {
        switch style {
        case .oil:
            return oilMaterial
        case .watercolor:
            return watercolorMaterial
        case .ink:
            return inkMaterial
        case .neon:
            return neonMaterial
        default:
            return nil
        }
    }
    
    /// Whether materials have been loaded
    var materialsReady: Bool {
        isLoaded
    }
    
    /// Ensures all materials are loaded. Call early in app lifecycle.
    func ensureLoaded() {
        guard loadTask == nil, !isLoaded else { return }
        
        loadTask = Task { @MainActor in
            await loadAllMaterials()
            isLoaded = true
            loadTask = nil
        }
    }
    
    /// Wait for materials to be loaded
    func waitForLoad() async {
        if isLoaded { return }
        await loadTask?.value
    }
    
    // MARK: - Material Loading
    
    private func loadAllMaterials() async {
        async let oil = loadMaterial(named: "OilBrush")
        async let watercolor = loadMaterial(named: "WatercolorBrush")
        async let ink = loadMaterial(named: "InkBrush")
        async let neon = loadMaterial(named: "NeonBrush")
        
        oilMaterial = await oil
        watercolorMaterial = await watercolor
        inkMaterial = await ink
        neonMaterial = await neon
        
        let loadedCount = [oilMaterial, watercolorMaterial, inkMaterial, neonMaterial]
            .compactMap { $0 }.count
        
        print("🎨 PainterlyMaterialManager: Loaded \(loadedCount)/4 materials")
    }
    
    private func loadMaterial(named name: String) async -> ShaderGraphMaterial? {
        // Try loading from RealityKitContent bundle
        do {
            // First try: Load from Materials folder in rkassets
            if let url = realityKitContentBundle.url(
                forResource: name,
                withExtension: "usda",
                subdirectory: "RealityKitContent.rkassets/Materials"
            ) {
                var material = try await ShaderGraphMaterial(named: name, from: url)
                configureMaterial(&material)
                print("🎨 Loaded \(name) from Materials folder")
                return material
            }
            
            // Second try: Load from root of rkassets
            if let url = realityKitContentBundle.url(
                forResource: name,
                withExtension: "usda",
                subdirectory: "RealityKitContent.rkassets"
            ) {
                var material = try await ShaderGraphMaterial(named: name, from: url)
                configureMaterial(&material)
                print("🎨 Loaded \(name) from rkassets root")
                return material
            }
            
            // Third try: Use bundle's built-in material loading
            var material = try await ShaderGraphMaterial(
                named: "/Root/\(name)",
                from: realityKitContentBundle
            )
            configureMaterial(&material)
            print("🎨 Loaded \(name) from bundle")
            return material
            
        } catch {
            print("⚠️ Failed to load \(name) material: \(error)")
            return nil
        }
    }
    
    private func configureMaterial(_ material: inout ShaderGraphMaterial) {
        // Configure for double-sided rendering (ribbons need this)
        if #available(visionOS 2.0, *) {
            material.faceCulling = .none
        }
    }
    
    // MARK: - Material Parameter Updates
    
    /// Creates a copy of a material with updated vertex color
    /// Note: ShaderGraphMaterial reads vertex colors via geomprop, so we don't need to set parameters
    /// The vertex color is already in the mesh and the shader reads it
    func configuredMaterial(
        base: ShaderGraphMaterial,
        for stroke: SpaceStroke
    ) -> ShaderGraphMaterial {
        // Currently, the materials read vertex color from the mesh geometry
        // If you need to pass additional parameters (like emission intensity),
        // you would set them here:
        
        var material = base
        
        // Example: If you add parameters to your .usda files, set them like this:
        // try? material.setParameter(name: "EmissionIntensity", value: .float(Float(stroke.emission)))
        
        return material
    }
}

#endif
