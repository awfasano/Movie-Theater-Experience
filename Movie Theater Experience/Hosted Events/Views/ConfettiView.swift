import SwiftUI

/// A lightweight confetti overlay using SwiftUI's Canvas and TimelineView.
/// Usage: `ConfettiView().ignoresSafeArea()`
struct ConfettiView: View {
    var intensity: Int = 120          // number of particles
    var colors: [Color] = [.pink, .orange, .yellow, .green, .mint, .blue, .purple]
    var seed: UInt64 = 42             // for repeatable randomness per instance
    var speed: CGFloat = 120          // base falling speed (points/sec)
    var spin: CGFloat = .pi           // base spin (radians/sec)
    var spread: CGFloat = .pi / 6     // side-to-side drift amplitude

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: Date.now, by: 1.0/60.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let rng = RandomNumberGeneratorWithSeed(seed: seed)
                let particles = ConfettiParticle.particles(count: intensity, in: size, seedRNG: rng)

                for p in particles {
                    let state = p.state(at: t, in: size, speed: speed, spin: spin, spread: spread)
                    guard state.visible else { continue }

                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: state.position.x, y: state.position.y)
                    transform = transform.rotated(by: state.rotation)
                    transform = transform.scaledBy(x: state.scale.width, y: state.scale.height)

                    context.withCGContext { cg in
                        cg.concatenate(transform)
                        let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
                        if let cgColor = p.color(in: colors).cgColor {
                            cg.setFillColor(cgColor)
                            cg.fill(rect)
                        }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Particle Model

private struct ConfettiParticle: Hashable {
    var id: Int
    var baseX: CGFloat
    var delay: Double
    var size: CGSize
    var hueIndex: Int
    var flip: Bool

    static func particles(count: Int, in size: CGSize, seedRNG: some RandomNumberGenerator) -> [ConfettiParticle] {
        var rng = seedRNG
        return (0..<max(0, count)).map { i in
            let baseX = CGFloat.random(in: 0...size.width, using: &rng)
            let delay = Double.random(in: 0...2, using: &rng)
            let w = CGFloat.random(in: 6...14, using: &rng)
            let h = CGFloat.random(in: 8...18, using: &rng)
            let flip = Bool.random(using: &rng)
            let hueIndex = Int.random(in: 0...6, using: &rng)
            return ConfettiParticle(id: i, baseX: baseX, delay: delay, size: CGSize(width: w, height: h), hueIndex: hueIndex, flip: flip)
        }
    }

    func color(in palette: [Color]) -> Color {
        guard !palette.isEmpty else { return .white }
        return palette[hueIndex % palette.count]
    }

    func state(at time: TimeInterval, in canvasSize: CGSize, speed: CGFloat, spin: CGFloat, spread: CGFloat) -> (position: CGPoint, rotation: CGFloat, scale: CGSize, visible: Bool) {
        // Start above the screen and loop every 4 seconds
        let period: Double = 4
        let localT = (time + Double(id) * 0.07 + delay).truncatingRemainder(dividingBy: period)
        let progress = CGFloat(localT / period)

        let y = -40 + progress * (canvasSize.height + 80)
        let drift = sin(progress * .pi * 2 + CGFloat(id) * 0.3) * spread * (20 + CGFloat(id % 7) * 4)
        let x = baseX + drift

        let rot = progress * spin * (flip ? -1 : 1) + CGFloat(id % 5) * 0.2
        let s = 0.8 + 0.4 * sin(progress * .pi * 4 + CGFloat(id))
        let scale = CGSize(width: s, height: max(0.6, 1.2 - s))

        let visible = x > -60 && x < canvasSize.width + 60 && y < canvasSize.height + 60
        return (CGPoint(x: x, y: y), rot, scale, visible)
    }
}

// MARK: - Seeded RNG

private struct RandomNumberGeneratorWithSeed: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        // Xoroshiro64*
        var x = state
        x &+= 0x9E3779B97F4A7C15
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        state = x
        return z
    }
}

// Convenience to get CGColor from Color without forcing platform-specific imports
private extension Color {
    var cgColor: CGColor? {
        #if canImport(UIKit)
        return UIColor(self).cgColor
        #elseif canImport(AppKit)
        return NSColor(self).cgColor
        #else
        return nil
        #endif
    }
}
