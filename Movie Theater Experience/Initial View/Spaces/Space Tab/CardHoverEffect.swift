import SwiftUI
// ============================================================
// MARK: - Gaze State Environment (Single Source of Truth)
// ============================================================

private struct GazeActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var gazeActive: Bool {
        get { self[GazeActiveKey.self] }
        set { self[GazeActiveKey.self] = newValue }
    }
}

// ============================================================
// MARK: - Custom Hover Effect: Tilt + Gaze Sync
// ============================================================

@available(iOS 18.0, visionOS 2.0, *)
struct TiltGlowHoverEffect: CustomHoverEffect {
    var maxTiltAngle: CGFloat = 8.0
    var activeScale: CGFloat = 1.06

    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, _ in
            let tilt = isActive ? maxTiltAngle * 0.15 : 0
            return effect.animation(.spring(response: 0.35, dampingFraction: 0.85)) {
                $0
                    .scaleEffect(isActive ? activeScale : 1.0)
                    .rotationEffect(.degrees(tilt))
                    .offset(y: isActive ? -0.5 : 0)
            }
        }
    }
}

@available(iOS 18.0, visionOS 2.0, *)
private struct TiltIfAvailable: ViewModifier {
    var maxTiltAngle: CGFloat = 8.0
    var activeScale: CGFloat = 1.06
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: cornerRadius))
            .hoverEffect(
                TiltGlowHoverEffect(
                    maxTiltAngle: maxTiltAngle,
                    activeScale: activeScale
                )
            )
    }
}

private struct LegacyLiftHoverEffect: ViewModifier {
    func body(content: Content) -> some View {
        content.hoverEffect(.lift)
    }
}

extension View {
    func interactiveCardHover(cornerRadius: CGFloat = 24) -> some View {
        modifier(
            InteractiveCardHover(cornerRadius: cornerRadius)
        )
    }
}

private struct InteractiveCardHover: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        if #available(iOS 18.0, visionOS 2.0, *) {
            content.modifier(TiltIfAvailable(cornerRadius: cornerRadius))
        } else {
            content.modifier(LegacyLiftHoverEffect())
        }
    }
}

// ============================================================
// MARK: - CardChromeBackground
// ============================================================

struct CardChromeBackground: View {
    let isHighlighted: Bool
    let corner: CGFloat

    private var base: some Shape {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
    }

    private var glowGradient: LinearGradient {
        LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            base.fill(.ultraThinMaterial)

            base.fill(glowGradient.opacity(0.15))
                .opacity(isHighlighted ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isHighlighted)

            base.stroke(
                isHighlighted ? glowGradient : LinearGradient(colors: [Color.secondary.opacity(0.15)], startPoint: .leading, endPoint: .trailing),
                lineWidth: isHighlighted ? 2.5 : 1
            )
            .animation(.easeInOut(duration: 0.25), value: isHighlighted)

            ZStack {
                base.stroke(glowGradient, lineWidth: 8)
                    .padding(-20)
                    .blur(radius: 20)
                    .blendMode(.plusLighter)
                    .opacity(isHighlighted ? 0.6 : 0)

                base.stroke(glowGradient, lineWidth: 6)
                    .padding(-15)
                    .blur(radius: 12)
                    .blendMode(.plusLighter)
                    .opacity(isHighlighted ? 0.8 : 0)

                base.stroke(glowGradient, lineWidth: 4)
                    .padding(-8)
                    .blur(radius: 6)
                    .blendMode(.plusLighter)
                    .opacity(isHighlighted ? 1.0 : 0)
            }
            .animation(.easeInOut(duration: 0.25), value: isHighlighted)
            .allowsHitTesting(false)
        }
        .compositingGroup()
    }
}

// ============================================================
// MARK: - CardHeaderImage
// ============================================================

struct CardHeaderImage: View {
    let thumbnailURL: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let url = URL(string: thumbnailURL ?? "") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .padding()
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "cube.transparent")
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            }
            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
        }
        .clipped()
    }
}

// ============================================================
// MARK: - SpaceCard
// ============================================================
