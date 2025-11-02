//
//  SpaceDrawingWindow.swift
//  Movie Theater Experience
//
//  Created by GPT-5 Codex on 3/16/25.
//

import SwiftUI

struct SpaceDrawingWindow: View {
    @EnvironmentObject private var viewModel: SpaceDrawingViewModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isShowingGuide = false
    
    private let brushGridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 135), spacing: 12)
    ]
    private var selectedColorHex: String {
        viewModel.selectedColor.toHex?.uppercased() ?? "--"
    }
    
    private var overlayBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isOverlayVisible },
            set: { viewModel.setOverlayVisibility($0) }
        )
    }
    
    private var metallicBinding: Binding<Double> {
        Binding(
            get: { viewModel.selectedMetallic },
            set: { viewModel.updateMetallic($0) }
        )
    }
    
    private var roughnessBinding: Binding<Double> {
        Binding(
            get: { viewModel.selectedRoughness },
            set: { viewModel.updateRoughness($0) }
        )
    }
    private var emissiveBinding: Binding<Double> {
        Binding(
            get: { viewModel.selectedEmissive },
            set: { viewModel.updateEmissive($0) }
        )
    }
    private var emissiveColorBinding: Binding<Color> {
        Binding(
            get: { viewModel.selectedEmissiveColor },
            set: { viewModel.updateEmissiveColor($0) }
        )
    }
    private var widthBinding: Binding<Double> {
        Binding(
            get: { viewModel.selectedWidth },
            set: { viewModel.updateWidth($0) }
        )
    }
    private var colorBinding: Binding<Color> {
        Binding(
            get: { viewModel.selectedColor },
            set: { viewModel.updateColor($0) }
        )
    }
    
    private var depthBinding: Binding<Double> {
        Binding(
            get: { viewModel.selectedDepth },
            set: { viewModel.updateDepth($0) }
        )
    }
    
    private var depthLockBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isDepthLocked },
            set: { viewModel.setDepthLock($0) }
        )
    }
    
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { if !$0 { viewModel.lastError = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    instructionsCard
                    overlayToggle
                    visibilityToggle
                    brushPalette
                    colorPickerSection
                    thicknessPicker
                    depthSlider
                    toolSelector
                    materialSliders
                    actionButtons
                }
                .padding(20)
            }
        }
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, minHeight: 520)
        .background(.ultraThinMaterial)
        .alert("Drawing Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.lastError = nil }
        } message: {
            if let message = viewModel.lastError {
                Text(message)
            }
        }
        .sheet(isPresented: $isShowingGuide) {
            SpaceDrawingGuideView()
                .environmentObject(viewModel)
        }
    }
    
    private var header: some View {
        HStack {
            Text("Drawing Tools")
                .font(.headline)
            Spacer()
            Button(action: { dismissWindow() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 10)
    }
    
    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick start")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(icon: "cube.transparent", text: "Toggle \"Show drawing volume\" to view the shared layout and \"Show saved drawings\" for any existing strokes.")
                instructionRow(icon: "hand.point.up.left.fill", text: "Extend your index finger (or click-drag with a mouse) to begin drawing in mid-air.")
            }
            Button {
                isShowingGuide = true
            } label: {
                Label("Open detailed guide", systemImage: "questionmark.circle")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
}

private func instructionRow(icon: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
    private var overlayToggle: some View {
        Toggle(isOn: overlayBinding) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Show drawing volume")
                    .font(.subheadline.weight(.semibold))
                Text("Toggles the collaborative sketch volume in front of the theater stage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var visibilityToggle: some View {
        Toggle(isOn: Binding(
            get: { viewModel.strokesAreVisible },
            set: { viewModel.setDrawingVisibility($0) }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Show saved drawings")
                    .font(.subheadline.weight(.semibold))
                Text("Hide drawings without deleting them when you want a clean volume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var brushPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Brush presets")
                .font(.subheadline.weight(.semibold))
            Text("Pick a preset to swap style, color, width, and material defaults in one tap.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: brushGridColumns, spacing: 12) {
                ForEach(viewModel.availableBrushes) { brush in
                    Button {
                        viewModel.select(brush: brush)
                    } label: {
                        brushCard(for: brush)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func brushCard(for brush: SpaceDrawingBrushOption) -> some View {
        let isSelected = viewModel.selectedBrush.id == brush.id && viewModel.selectedBrush.style == brush.style
        return VStack(alignment: .leading, spacing: 8) {
            brushPreview(for: brush)
                .frame(height: 38)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(brush.displayName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(brush.style.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(brush.style.description)
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.7))
                .lineLimit(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(isSelected ? 0.2 : 0.08), radius: isSelected ? 6 : 2, x: 0, y: isSelected ? 3 : 1)
    }

    @ViewBuilder
    private func brushPreview(for brush: SpaceDrawingBrushOption) -> some View {
        let base = brush.color
        switch brush.style {
        case .tubular:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [base.opacity(0.85), base.opacity(0.65)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        .blur(radius: 0.3)
                        .offset(y: -0.6)
                )
        case .flat:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(base.opacity(0.85))
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 2)
        case .ribbon:
            ZStack {
                Capsule()
                    .fill(base.opacity(0.35))
                    .scaleEffect(x: 1.05, y: 1.2, anchor: .center)
                    .offset(y: 6)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [base.opacity(0.6), base.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(-8))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [base.opacity(0.35), base.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 14)
                    .rotationEffect(.degrees(10))
            }
        case .classicCylinder:
            ZStack {
                Capsule()
                    .fill(base.opacity(0.18))
                HStack(spacing: 4) {
                    Capsule()
                        .fill(base.opacity(0.7))
                        .frame(width: 24, height: 14)
                    Capsule()
                        .fill(base.opacity(0.5))
                        .frame(width: 20, height: 14)
                    Capsule()
                        .fill(base.opacity(0.35))
                        .frame(width: 16, height: 14)
                }
                .padding(.horizontal, 6)
            }
        case .box:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [base.opacity(0.8), base.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
        }
    }

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stroke color")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                ColorPicker("", selection: colorBinding, supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.gray.opacity(0.12))
                    )
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(viewModel.selectedColor)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hex: \(selectedColorHex)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("Adjust hue, brightness, or transparency to personalize the active brush.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var thicknessPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stroke thickness")
                .font(.subheadline.weight(.semibold))
            Text("Also controls the eraser radius.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Slider(value: widthBinding, in: viewModel.widthRange)
                Text(viewModel.selectedWidth.formatted(.number.precision(.fractionLength(3))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            HStack(spacing: 12) {
                ForEach(viewModel.availableWidths, id: \.self) { width in
                    Button {
                        viewModel.selectWidth(width)
                    } label: {
                        Capsule()
                            .fill(viewModel.selectedWidth == width ? Color.accentColor.opacity(0.35) : Color.gray.opacity(0.2))
                            .frame(width: 46, height: max(CGFloat(width) * 520, 4))
                            .overlay(
                                Capsule()
                                    .stroke(viewModel.selectedWidth == width ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var toolSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tool")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                toolButton(
                    title: "Brush",
                    systemImage: "paintbrush.pointed",
                    isActive: viewModel.selectedTool == .brush
                ) {
                    viewModel.select(tool: .brush)
                }
                
                toolButton(
                    title: "Eraser",
                    systemImage: "eraser",
                    isActive: viewModel.selectedTool == .eraser
                ) {
                    viewModel.select(tool: .eraser)
                }
            }
        }
    }
    
    private var depthSlider: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Depth offset (m)")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Front")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.selectedDepth.formatted(.number.precision(.fractionLength(2))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Back")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: depthBinding, in: viewModel.depthRange)
            }
            Toggle(isOn: depthLockBinding) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isDepthLocked ? "lock.fill" : "lock.open")
                    Text("Lock depth plane")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            Text("Keep strokes on the same depth when drawing by hand. Adjust the slider to move the locked plane.")
                .font(.caption2)
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
    }
    
    private func toolButton(title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isActive ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.accentColor : Color.gray.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    private var materialSliders: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Material response")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Metallic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.selectedMetallic.formatted(.number.precision(.fractionLength(2))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: metallicBinding, in: viewModel.metallicRange)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Roughness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.selectedRoughness.formatted(.number.precision(.fractionLength(2))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: roughnessBinding, in: viewModel.roughnessRange)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Emission")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.selectedEmissive.formatted(.number.precision(.fractionLength(2))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: emissiveBinding, in: viewModel.emissiveRange)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Emission color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        viewModel.updateEmissiveColor(viewModel.selectedColor)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                ColorPicker("Emission color", selection: emissiveColorBinding, supportsOpacity: false)
                    .labelsHidden()
                Text("Defaults to your brush color—pick a different tint if you want the glow to pop.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                pillActionButton("Undo", systemImage: "arrow.uturn.backward", isEnabled: viewModel.canUndo) {
                    viewModel.undoLastStroke()
                }
                pillActionButton("Clear board", systemImage: "trash", role: .destructive) {
                    viewModel.clearAll()
                }
                pillActionButton("Animate", systemImage: "sparkles", isEnabled: viewModel.strokesAreVisible && !viewModel.strokes.isEmpty) {
                    viewModel.replayStrokeAnimations()
                }
            }
            Text("Undo reverts the latest stroke, Clear board wipes everything, and Animate replays the saved stroke reveal.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    private func pillActionButton(_ title: String, systemImage: String, role: ButtonRole? = nil, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isEnabled ? Color.accentColor.opacity(role == .destructive ? 0.2 : 0.25) : Color.gray.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(isEnabled ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}

private struct SpaceDrawingGuideView: View {
    @EnvironmentObject var viewModel: SpaceDrawingViewModel
    @Environment(\.dismiss) private var dismiss
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    guideSection(
                        title: "Get set up",
                        items: [
                            ("Display the workspace", "Turn on \"Show drawing volume\" to reveal the 10 × 10 × 10 m cube where everyone can sketch."),
                            ("Reveal saved art", "Flip on \"Show saved drawings\" to pull existing strokes from Firestore into the scene."),
                            ("Pick a brush", "Choose a preset or customise width, colour, metallic, roughness, and emission to dial in the look."),
                            ("Tune the glow", "Emission colour matches your brush by default—change it to cast a different hue while the stroke is revealed."),
                            ("Frame the depth plane", "Use the depth slider to position the base plane. Lock it when you want every stroke on a consistent layer.")
                        ]
                    )
                    
                    guideSection(
                        title: "Draw in space",
                        items: [
                            ("Hand tracking", "Extend your index finger and pinch/drag to emit points. Relaxing your finger ends the stroke."),
                            ("Mouse or trackpad", "Click-drag anywhere inside the volume to sketch. Release to finish."),
                            ("Controllers", "Use the on-screen cursor: press and hold the primary button or trigger to draw."),
                            ("Keep things smooth", "Thinner widths create longer continuous strokes, while wider widths automatically segment for stability.")
                        ]
                    )
                    
                    guideSection(
                        title: "Depth & positioning",
                        items: [
                            ("Lock the plane", "Toggle \"Lock depth plane\" to keep hand-drawn strokes anchored to the current depth."),
                            ("Adjust on the fly", "Unlock to resume capturing natural hand depth, then re-lock once you have the plane you like."),
                            ("Finger preview", "The glowing indicator mirrors your brush size and colour—use it to judge where the next point will land.")
                        ]
                    )
                    
                    guideSection(
                        title: "Manage strokes",
                        items: [
                            ("Undo & redo", "Tap Undo to remove the latest stroke. For now redo isn’t supported—use Undo selectively."),
                            ("Clear the board", "Use Clear board to wipe the entire volume. This deletes remote data for everyone."),
                            ("Eraser tool", "Switch to the eraser to scrub away portions of strokes. Eraser size tracks your selected width."),
                            ("Animate saved art", "Use the Animate button any time to replay the reveal effect for all currently visible strokes.")
                        ]
                    )
                    
                    guideSection(
                        title: "Collaboration tips",
                        items: [
                            ("Stay in sync", "Everyone connected to the space streams strokes live via Firestore; give remote users a moment to load."),
                            ("Mind the volume", "All drawing happens inside the cube. If strokes disappear, make sure your overlay is enabled and your anchor is configured."),
                            ("Optimise performance", "Very large, wide strokes get chunked automatically to keep rendering responsive.")
                        ]
                    )
                    
                    guideSection(
                        title: "Troubleshooting",
                        items: [
                            ("No strokes appear", "Confirm \"Show saved drawings\" is on and the space is activated. If the anchor detached, call configureSceneRoot again."),
                            ("Hand won’t draw", "Check that the overlay is visible and your finger is clearly extended. If depth is locked, ensure the plane is inside the volume."),
                            ("Stroke floats", "Toggle the depth lock or re-run Animate—everything re-renders using the latest anchor and material settings.")
                        ]
                    )
                    
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Space Drawing Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func guideSection(title: String, items: [(String, String)]) -> some View {
        let entries = Array(items.enumerated())
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entries, id: \.offset) { entry in
                    let item = entry.element
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.0)
                            .font(.subheadline.weight(.semibold))
                        Text(item.1)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if entry.offset != entries.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
