import SwiftUI
import GreenCore

/// Pick every way you get around that emits carbon (or none), then set the weekly distance for each. Each
/// mode shows its own yearly carbon so the trade-offs are visible while answering.
struct CommutePlanner: View {
    @Binding var distances: [CommuteMode: Double]

    /// Starting distance for a newly picked mode, km per week.
    private static let defaultKm = 40.0

    private var selection: Binding<Set<CommuteMode>> {
        Binding(get: { Set(distances.keys) }, set: { newValue in
            var updated = distances.filter { newValue.contains($0.key) }
            for mode in newValue.subtracting(distances.keys) { updated[mode] = Self.defaultKm }
            distances = updated
        })
    }

    private var modes: [CommuteMode] {
        CommuteMode.allCases.filter { distances[$0] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CommuteScene(modes: modes)
            Text("Select any that apply").font(.footnote).foregroundStyle(.secondary)
            MultiChoiceChips(selection: selection)
            ForEach(modes, id: \.self) { mode in
                VStack(alignment: .leading, spacing: 4) {
                    DistanceSlider(title: mode.profileLabel, kmPerWeek: Binding(
                        get: { distances[mode] ?? 0 }, set: { distances[mode] = $0 }),
                                   identifier: "onboarding.distance.\(mode.rawValue)")
                    Text(yearlyLine(mode))
                        .font(.caption)
                        .foregroundStyle((LifestyleEstimate.kgPerKm[mode] ?? 0) > 0.05 ? Theme.warning : Theme.leaf)
                        .contentTransition(.numericText())
                }
                .padding(12)
                .background(.fill.quaternary, in: .rect(cornerRadius: 14))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if distances.isEmpty {
                Label("None selected: no regular travel by car, transit or e-bike. Walking and cycling count as zero.",
                      systemImage: "figure.walk")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.snappy, value: modes)
    }

    private func yearlyLine(_ mode: CommuteMode) -> String {
        let kg = (LifestyleEstimate.kgPerKm[mode] ?? 0) * (distances[mode] ?? 0) * 52
        guard kg > 0 else { return "≈ 0 carbon from \(mode.profileLabel.lowercased())" }
        return "≈ \(DisplayUnits.carbon(kg: kg)) a year"
    }
}

/// A little street scene: each picked way of getting around drives by (a car puffs exhaust, an electric car
/// doesn't); with none picked, someone strolls past. Drawn in one Canvas at up to 30 fps, still with Reduce Motion.
struct CommuteScene: View {
    let modes: [CommuteMode]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ArtPanel(tint: .blue, height: 104) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                } symbols: {
                    Image(systemName: "cloud.fill").font(.system(size: 26)).foregroundStyle(.white.opacity(0.85)).tag("cloud")
                    Image(systemName: "sun.max.fill").font(.system(size: 22)).foregroundStyle(.yellow).tag("sun")
                    Image(systemName: "tree.fill").font(.system(size: 26)).foregroundStyle(Theme.leaf.gradient).tag("tree")
                    Image(systemName: "figure.walk").font(.system(size: 24)).foregroundStyle(Theme.leaf).tag("walk")
                    ForEach(CommuteMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.sceneSymbol)
                            .font(.system(size: 26))
                            .foregroundStyle(mode.sceneColor.gradient)
                            .tag(mode.rawValue)
                    }
                }
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let roadTop = size.height - 30
        let span = size.width + 120
        /// Position along a looping track: enters at the left edge, leaves at the right.
        func x(speed: Double, phase: Double) -> Double {
            (time * speed + phase).truncatingRemainder(dividingBy: span) - 60
        }

        if let sun = context.resolveSymbol(id: "sun") { context.draw(sun, at: CGPoint(x: size.width - 26, y: 22)) }
        if let cloud = context.resolveSymbol(id: "cloud") {
            context.draw(cloud, at: CGPoint(x: x(speed: 6, phase: 40), y: 22))
            var faded = context
            faded.opacity = 0.6
            faded.draw(cloud, at: CGPoint(x: x(speed: 4, phase: 260), y: 34))
        }
        if let tree = context.resolveSymbol(id: "tree") {
            for treeX in stride(from: 30.0, to: size.width, by: 110) {
                context.draw(tree, at: CGPoint(x: treeX, y: roadTop - 14))
            }
        }

        // The road and its dashed centre line.
        context.fill(Path(CGRect(x: 0, y: roadTop, width: size.width, height: 30)), with: .color(.gray.opacity(0.45)))
        var dashes = Path()
        dashes.move(to: CGPoint(x: 0, y: roadTop + 15))
        dashes.addLine(to: CGPoint(x: size.width, y: roadTop + 15))
        context.stroke(dashes, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 2, dash: [12, 10]))

        guard !modes.isEmpty else {
            if let walker = context.resolveSymbol(id: "walk") {
                context.draw(walker, at: CGPoint(x: x(speed: 16, phase: 80), y: roadTop - 12))
            }
            return
        }
        for (index, mode) in modes.enumerated() {
            guard let symbol = context.resolveSymbol(id: mode.rawValue) else { continue }
            // Alternate lanes; the far lane is drawn first so the near one passes in front.
            let lane = index % 2 == 0 ? roadTop + 6 : roadTop + 18
            let position = CGPoint(x: x(speed: mode.sceneSpeed, phase: Double(index) * span / Double(modes.count)),
                                   y: lane - symbol.size.height / 2 + 6)
            if mode == .car {
                // A few puffs of exhaust trailing the car, fading as they drift.
                for puff in 0..<3 {
                    let age = (time * 2 + Double(puff) / 3).truncatingRemainder(dividingBy: 1)
                    let radius = 3 + age * 5
                    let center = CGPoint(x: position.x - symbol.size.width / 2 - 4 - age * 18, y: position.y + 6 - age * 6)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(.gray.opacity(0.45 * (1 - age))))
                }
            }
            context.draw(symbol, at: position)
        }
    }
}

private extension CommuteMode {
    var sceneSymbol: String {
        switch self {
        case .car, .electricCar: "car.side.fill"
        case .transit: "train.side.front.car"
        case .eBike: "bicycle"
        }
    }

    var sceneColor: Color {
        switch self {
        case .car: .orange
        case .electricCar: Theme.leaf
        case .transit: .blue
        case .eBike: .teal
        }
    }

    /// Points per second across the scene.
    var sceneSpeed: Double {
        switch self {
        case .car, .electricCar: 70
        case .transit: 48
        case .eBike: 36
        }
    }
}
