import SwiftUI
import GreenCore

/// Numbered glass pins over each component (spec §6), matching the numbers in the component list. Pins sit
/// at the center of each item's box, so a loose box still points at the item; the selected item also gets
/// scanner-style corner brackets and a name label. Pins pop in one after another inside a
/// `GlassEffectContainer`. Overlay this on a `ResultPhoto`.
struct ComponentHotspots: View {
    let components: [Component]
    let filter: ResultMetricFilter
    let selectedID: Component.ID?
    let onSelect: (Component) -> Void

    @State private var revealed = 0
    @Namespace private var glass

    private let pinSize: CGFloat = 30

    private var ranked: [Component] { ResultInsights.ranked(components, by: filter.shareMetric) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let selected = ranked.first(where: { $0.id == selectedID }) {
                    CornerBrackets()
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(0.45), radius: 4)
                        .frame(width: rect(for: selected, in: geometry.size).width,
                               height: rect(for: selected, in: geometry.size).height)
                        .position(x: rect(for: selected, in: geometry.size).midX,
                                  y: rect(for: selected, in: geometry.size).midY)
                        .transition(.opacity.combined(with: .scale(scale: 1.08)))
                        .allowsHitTesting(false)
                }
                GlassEffectContainer(spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, component in
                            if index < revealed {
                                pin(component, number: index + 1, in: geometry.size)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
            }
            .animation(.smooth(duration: 0.25), value: selectedID)
        }
        .task(id: components.map(\.id)) { await reveal() }
    }

    private func rect(for component: Component, in size: CGSize) -> CGRect {
        let box = component.boundingBox.clamped
        return CGRect(x: box.x * size.width, y: box.y * size.height,
                      width: box.width * size.width, height: box.height * size.height)
    }

    private func pin(_ component: Component, number: Int, in size: CGSize) -> some View {
        let share = ResultInsights.share(of: component, metric: filter.shareMetric, in: components)
        let isSelected = component.id == selectedID
        let center = rect(for: component, in: size)
        // Keep the pin (and its label) inside the photo.
        let x = min(max(center.midX, pinSize), size.width - pinSize)
        let y = min(max(center.midY, pinSize), size.height - pinSize)

        return Button { onSelect(component) } label: {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .frame(width: pinSize - 8, height: pinSize - 8)
                    .background(Theme.carbonShareTint(share).gradient, in: .circle)
                if isSelected {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(component.name).font(.caption.weight(.semibold)).lineLimit(1)
                        if let value = component.metrics[filter.shareMetric] {
                            Text(value.formatted).font(.caption2.monospacedDigit()).opacity(0.85)
                        }
                    }
                    .padding(.trailing, 6)
                    .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .padding(4)
            .frame(maxWidth: 220)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID(component.id, in: glass)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .position(x: x, y: y)
        .accessibilityLabel(accessibilityText(component, number: number, share: share))
        .accessibilityIdentifier("hotspot.\(component.name)")
    }

    private func accessibilityText(_ component: Component, number: Int, share: Double) -> String {
        "\(number). \(component.name), \(Int((share * 100).rounded()))% of \(filter.shareMetric.displayName.lowercased())"
    }

    /// Pops the pins in one after another so the container morphs them into place.
    private func reveal() async {
        revealed = 0
        for index in 1...max(components.count, 1) {
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.bouncy(duration: 0.45)) { revealed = index }
        }
    }
}

/// Four L-shaped corners around a rectangle, like a camera's focus frame.
struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(28, rect.width * 0.3, rect.height * 0.3)
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
        }
        return path
    }
}
