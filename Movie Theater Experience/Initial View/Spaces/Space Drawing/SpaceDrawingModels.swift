//
//  SpaceDrawingModels.swift
//  Movie Theater Experience
//
//  Created by GPT-5 Codex on 3/16/25.
//

import Foundation
import SwiftUI
import FirebaseFirestore
import simd

/// Represents a single sampled point in world space for the collaborative drawing volume.
struct SpaceDrawingPoint3D: Codable, Hashable {
    var x: Double
    var y: Double
    var z: Double
    var timestamp: Date?
    
    init(x: Double, y: Double, z: Double, timestamp: Date? = nil) {
        self.x = x
        self.y = y
        self.z = z
        self.timestamp = timestamp
    }
    
    init(position: SIMD3<Float>, timestamp: Date? = nil) {
        self.init(
            x: Double(position.x),
            y: Double(position.y),
            z: Double(position.z),
            timestamp: timestamp
        )
    }
    
    enum CodingKeys: String, CodingKey {
        case x, y, z, timestamp
        // Legacy keys (2D canvas)
        case u, v, depth
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let x = try container.decodeIfPresent(Double.self, forKey: .x),
           let y = try container.decodeIfPresent(Double.self, forKey: .y),
           let z = try container.decodeIfPresent(Double.self, forKey: .z) {
            self.init(x: x, y: y, z: z, timestamp: try container.decodeIfPresent(Date.self, forKey: .timestamp))
        } else {
            // Legacy fallback: map normalized UV back into the drawing volume plane.
            let u = try container.decode(Double.self, forKey: .u)
            let v = try container.decode(Double.self, forKey: .v)
            let depth = try container.decodeIfPresent(Double.self, forKey: .depth) ?? 0.0
            let position = SpaceDrawingConstants.legacyWorldPosition(for: u, v: v, depth: depth)
            self.init(position: position, timestamp: try container.decodeIfPresent(Date.self, forKey: .timestamp))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(z, forKey: .z)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
    }
    
    var simdVector: SIMD3<Float> {
        SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}

/// A stroke captured on the shared drawing surface.
struct SpaceStroke: Codable, Identifiable, Hashable {
    enum Style: String, Codable {
        case tubular
        case flat
        case ribbon
        case classicCylinder
        case box
    }
    @DocumentID var id: String?
    var strokeId: String
    var spaceId: String
    var userId: String
    var userName: String
    var colorHex: String
    var width: Double
    var isEraser: Bool
    var metallic: Double
    var roughness: Double
    var createdAt: Date
    var updatedAt: Date
    var points: [SpaceDrawingPoint3D]
    var isDeleted: Bool
    var emission: Double
    var style: Style
    var emissionColorHex: String?
    
    var color: Color {
        Color(hex: colorHex) ?? .white
    }
    
    var emissionColor: Color {
        if let hex = emissionColorHex, let color = Color(hex: hex) {
            return color
        }
        return self.color
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case strokeId
        case spaceId
        case userId
        case userName
        case colorHex
        case width
        case isEraser
        case metallic
        case roughness
        case createdAt
        case updatedAt
        case points
        case isDeleted
        case emission
        case emissionColorHex
        case style
    }
    
    init(
        id: String? = nil,
        strokeId: String,
        spaceId: String,
        userId: String,
        userName: String,
        colorHex: String,
        width: Double,
        isEraser: Bool,
        metallic: Double,
        roughness: Double,
        createdAt: Date,
        updatedAt: Date,
        points: [SpaceDrawingPoint3D],
        isDeleted: Bool,
        emission: Double = 0.0,
        style: Style = .tubular,
        emissionColorHex: String? = nil
    ) {
        self.id = id
        self.strokeId = strokeId
        self.spaceId = spaceId
        self.userId = userId
        self.userName = userName
        self.colorHex = colorHex
        self.width = width
        self.isEraser = isEraser
        self.metallic = metallic
        self.roughness = roughness
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.points = points
        self.isDeleted = isDeleted
        self.emission = emission
        self.style = style
        self.emissionColorHex = emissionColorHex
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.strokeId = try container.decode(String.self, forKey: .strokeId)
        self.spaceId = try container.decode(String.self, forKey: .spaceId)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.userName = try container.decode(String.self, forKey: .userName)
        self.colorHex = try container.decode(String.self, forKey: .colorHex)
        self.width = try container.decode(Double.self, forKey: .width)
        self.isEraser = try container.decode(Bool.self, forKey: .isEraser)
        self.metallic = try container.decodeIfPresent(Double.self, forKey: .metallic) ?? 0.0
        self.roughness = try container.decodeIfPresent(Double.self, forKey: .roughness) ?? 0.65
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.points = try container.decode([SpaceDrawingPoint3D].self, forKey: .points)
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.emission = try container.decodeIfPresent(Double.self, forKey: .emission) ?? 0.0
        let styleValue = try container.decodeIfPresent(String.self, forKey: .style) ?? Style.tubular.rawValue
        self.style = Style(rawValue: styleValue) ?? .tubular
        self.emissionColorHex = try container.decodeIfPresent(String.self, forKey: .emissionColorHex)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(strokeId, forKey: .strokeId)
        try container.encode(spaceId, forKey: .spaceId)
        try container.encode(userId, forKey: .userId)
        try container.encode(userName, forKey: .userName)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(width, forKey: .width)
        try container.encode(isEraser, forKey: .isEraser)
        try container.encode(metallic, forKey: .metallic)
        try container.encode(roughness, forKey: .roughness)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(points, forKey: .points)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(emission, forKey: .emission)
        try container.encode(style.rawValue, forKey: .style)
        try container.encodeIfPresent(emissionColorHex, forKey: .emissionColorHex)
    }
}

/// Brush configuration available to the user.
struct SpaceDrawingBrushOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let color: Color
    let width: Double
    let metallic: Double
    let roughness: Double
    let emissive: Double
    let style: SpaceStroke.Style
    let emissiveColorHex: String?
    
    var emissiveColor: Color? {
        guard let hex = emissiveColorHex else { return nil }
        return Color(hex: hex)
    }
}

enum SpaceDrawingConstants {
    static let collectionName = "drawings"
    static let maxPointCount = 15000
    static let maxStrokePoints = 600
    static let minPointDistanceSquared: Double = 0.0004 // meters squared (~2 cm)
    static let volumeSizeMeters = SIMD3<Float>(10.0, 10.0, 10.0)
    static let planeSizeMeters = SIMD2<Float>(volumeSizeMeters.x, volumeSizeMeters.y)
    static let planeDistance: Float = -volumeSizeMeters.z / 2
    static let planeHeight: Float = volumeSizeMeters.y / 2
    static let defaultBrushes: [SpaceDrawingBrushOption] = [
        SpaceDrawingBrushOption(
            id: "tube-white",
            displayName: "Luminous Tube",
            color: .white,
            width: 0.004,
            metallic: 0.08,
            roughness: 0.55,
            emissive: 0.0,
            style: .tubular,
            emissiveColorHex: nil
        ),
        SpaceDrawingBrushOption(
            id: "tube-cobalt",
            displayName: "Cobalt Tube",
            color: Color(hex: "#4DA3FF") ?? .blue,
            width: 0.004,
            metallic: 0.35,
            roughness: 0.4,
            emissive: 0.1,
            style: .tubular,
            emissiveColorHex: nil
        ),
        SpaceDrawingBrushOption(
            id: "flat-marker",
            displayName: "Flat Marker",
            color: Color(hex: "#F7CE68") ?? .yellow,
            width: 0.006,
            metallic: 0.12,
            roughness: 0.82,
            emissive: 0.0,
            style: .flat,
            emissiveColorHex: nil
        ),
        SpaceDrawingBrushOption(
            id: "ribbon-oil",
            displayName: "Oil Ribbon",
            color: Color(hex: "#FF76C8") ?? .pink,
            width: 0.007,
            metallic: 0.18,
            roughness: 0.48,
            emissive: 0.25,
            style: .ribbon,
            emissiveColorHex: nil
        ),
        SpaceDrawingBrushOption(
            id: "ribbon-forest",
            displayName: "Forest Ribbon",
            color: Color(hex: "#4FF2A7") ?? .green,
            width: 0.006,
            metallic: 0.22,
            roughness: 0.52,
            emissive: 0.18,
            style: .ribbon,
            emissiveColorHex: nil
        ),
        SpaceDrawingBrushOption(
            id: "classic-ember",
            displayName: "Classic Cylinder",
            color: Color(hex: "#FF9E4F") ?? .orange,
            width: 0.004,
            metallic: 0.2,
            roughness: 0.45,
            emissive: 0.0,
            style: .classicCylinder,
            emissiveColorHex: nil
        ),
        SpaceDrawingBrushOption(
            id: "block-ink",
            displayName: "Block Stroke",
            color: Color(hex: "#A0AEC0") ?? .gray,
            width: 0.005,
            metallic: 0.12,
            roughness: 0.58,
            emissive: 0.05,
            style: .box,
            emissiveColorHex: nil
        ),
        SpaceDrawingBrushOption(
            id: "neon-spray",
            displayName: "Neon Spray",
            color: Color(hex: "#7C67FF") ?? .purple,
            width: 0.0035,
            metallic: 0.4,
            roughness: 0.35,
            emissive: 0.65,
            style: .tubular,
            emissiveColorHex: nil
        )
    ]
    static let availableLineWidths: [Double] = [0.0015, 0.0025, 0.004, 0.006, 0.01, 0.015, 0.022, 0.03]
    static let metallicRange: ClosedRange<Double> = 0.0...1.0
    static let roughnessRange: ClosedRange<Double> = 0.05...1.0
    static let emissiveRange: ClosedRange<Double> = 0.0...1.0
    
    static func legacyWorldPosition(for u: Double, v: Double, depth: Double) -> SIMD3<Float> {
        let width = Double(volumeSizeMeters.x)
        let height = Double(volumeSizeMeters.y)
        let depthRange = Double(volumeSizeMeters.z)
        let x = (u - 0.5) * width
        let y = (0.5 - v) * height
        let z = max(-depthRange / 2, min(depthRange / 2, depth))
        return SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}

extension SpaceStroke.Style {
    var displayName: String {
        switch self {
        case .tubular:
            return "Round Tube"
        case .flat:
            return "Flat Marker"
        case .ribbon:
            return "Oil Ribbon"
        case .classicCylinder:
            return "Classic Cylinder"
        case .box:
            return "Box Stroke"
        }
    }
    
    var description: String {
        switch self {
        case .tubular:
            return "Smooth, fully rounded stroke."
        case .flat:
            return "Wide, planar sweep for bold fills."
        case .ribbon:
            return "Organic ribbon with gentle twists."
        case .classicCylinder:
            return "Legacy segmented cylinder style."
        case .box:
            return "Rectangular beam with subtle depth."
        }
    }
}
