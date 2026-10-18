import SwiftUI

/// A few leaves drifting down behind the content, rocking side to side and turning over as real ones do, and in
/// Dark Mode a handful of blinking fireflies. Drawn in one canvas at 30 fps; it stops while off screen and is left
/// out entirely with Reduce Motion.
struct DriftingLeaves: View {
    /// Sprite names from `GreeneryArt.leafSprites`, one leaf each.
    let sprites: [String]
    var fireflies = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isVisible)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    if fireflies {
                        for (index, firefly) in Firefly.all.enumerated() {
                            firefly.draw(in: context, size: size, time: time, index: index)
                        }
                    }
                    for index in sprites.indices {
                        guard let leaf = context.resolveSymbol(id: index) else { continue }
                        LeafFall.all[index % LeafFall.all.count].draw(leaf, in: context, size: size, time: time)
                    }
                } symbols: {
                    ForEach(sprites.indices, id: \.self) { index in
                        Image(sprites[index])
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .tag(index)
                    }
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
        }
    }
}

/// One leaf's path down the screen: a slow fall with a pendulum swing, tilting into each swing and turning over.
private struct LeafFall {
    /// Seconds to cross the screen top to bottom.
    var period: Double
    /// Where in its fall the leaf starts (0–1), so leaves don't fall together.
    var phase: Double
    /// Horizontal centre of the swing, as a share of the width.
    var column: Double
    var swing: Double
    var swingPeriod: Double
    var tilt: Double
    var scale: Double

    static let all = [
        LeafFall(period: 27, phase: 0.08, column: 0.16, swing: 36, swingPeriod: 6.4, tilt: 38, scale: 1),
        LeafFall(period: 33, phase: 0.52, column: 0.78, swing: 44, swingPeriod: 7.6, tilt: 46, scale: 0.85),
        LeafFall(period: 24, phase: 0.77, column: 0.42, swing: 30, swingPeriod: 5.5, tilt: 32, scale: 0.72),
        LeafFall(period: 30, phase: 0.3, column: 0.62, swing: 38, swingPeriod: 6.9, tilt: 40, scale: 0.9),
    ]

    func draw(_ leaf: GraphicsContext.ResolvedSymbol, in context: GraphicsContext, size: CGSize, time: Double) {
        let progress = (time / period + phase).truncatingRemainder(dividingBy: 1)
        let angle = 2 * .pi * (time / swingPeriod + phase)
        let x = column * size.width + swing * sin(angle)
        let y = -40 + progress * (size.height + 80)
        // Fade in under the top edge and out above the bottom, so leaves never pop in or out.
        let fade = min(progress / 0.06, (1 - progress) / 0.1, 1)
        var context = context
        context.opacity = 0.9 * fade
        context.translateBy(x: x, y: y)
        // Tilt follows the swing's speed, so the leaf leans into each sweep; the slower flip turns it over.
        context.rotate(by: .degrees(tilt * cos(angle) + 15 * sin(time / 4.3 + phase * 9)))
        let flip = cos(2 * .pi * time / (swingPeriod * 1.7) + phase * 5)
        context.scaleBy(x: scale * (0.3 + 0.7 * abs(flip)), y: scale)
        context.draw(leaf, at: .zero)
    }
}

/// A firefly wandering around a home spot and blinking.
private struct Firefly {
    /// Home position as shares of the width and height.
    var home: CGPoint
    var wander: Double
    var period: Double

    static let all = [
        Firefly(home: CGPoint(x: 0.12, y: 0.78), wander: 26, period: 9),
        Firefly(home: CGPoint(x: 0.3, y: 0.9), wander: 18, period: 7),
        Firefly(home: CGPoint(x: 0.86, y: 0.7), wander: 30, period: 11),
        Firefly(home: CGPoint(x: 0.7, y: 0.86), wander: 22, period: 8),
        Firefly(home: CGPoint(x: 0.92, y: 0.36), wander: 20, period: 10),
        Firefly(home: CGPoint(x: 0.06, y: 0.42), wander: 24, period: 12),
        Firefly(home: CGPoint(x: 0.52, y: 0.95), wander: 28, period: 9.5),
    ]

    func draw(in context: GraphicsContext, size: CGSize, time: Double, index: Int) {
        let seed = Double(index) * 1.7
        let x = home.x * size.width + wander * sin(time / period * 2 * .pi + seed)
        let y = home.y * size.height + wander * 0.6 * sin(time / (period * 0.7) * 2 * .pi + seed * 2)
        // Mostly dim, with a slow glow every few seconds.
        let blink = pow(max(0, sin(time / (period * 0.45) + seed * 3)), 3)
        let brightness = 0.15 + 0.85 * blink
        let center = CGPoint(x: x, y: y)
        let glow = CGRect(x: x - 10, y: y - 10, width: 20, height: 20)
        context.fill(Path(ellipseIn: glow), with: .radialGradient(
            Gradient(colors: [Self.glow.opacity(0.5 * brightness), Self.glow.opacity(0)]),
            center: center, startRadius: 0, endRadius: 10))
        context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)),
                     with: .color(Self.glow.opacity(brightness)))
    }

    private static let glow = Color(red: 0.92, green: 0.96, blue: 0.62)
}

#Preview {
    ZStack {
        PaperBackground()
        DriftingLeaves(sprites: GreeneryArt.leafSprites, fireflies: true)
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}
