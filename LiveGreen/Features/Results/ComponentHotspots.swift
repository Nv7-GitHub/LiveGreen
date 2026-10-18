import SwiftUI
import GreenCore

/// Numbered glass pins over each component (spec §6), with the list's numbers (`ScanBreakdown.numbers`, ranked once
/// by yearly carbon), so a number names the same item whatever the metric. Pins start at identify's point on each item,
/// else its box centre (`Component.pinAnchor`), and are spread apart (`PinLayout`) so none hides another; a pin
/// moved off its spot keeps a thin leader line to it. Colors say how large the item's yearly amount is
/// (`ImpactLevel`), not its share of the scene. The selected item also gets scanner-style corner brackets and a dark
/// callout beside its box, clamped inside the photo. Pins pop in one after another inside a `GlassEffectContainer`.
/// Overlay this on a `ResultPhoto`.
struct ComponentHotspots: View {
    let components: [Component]
    let filter: ResultMetricFilter
    /// Yearly values, shares and numbers, the same basis as the list.
    let breakdown: ScanBreakdown
    let selectedID: Component.ID?
    let onSelect: (Component) -> Void

    @State private var revealed = 0
    @Namespace private var glass

    private let pinSize: CGFloat = 30
    /// Center-to-center distance between pins: their size plus a gap wider than the glass container's blending
    /// spacing, so neighbouring pins never melt into one.
    private var pinSpacing: CGFloat { pinSize + 6 }

    /// Pins in number order, which is also the reveal order and the de-overlap priority.
    private var ordered: [Component] { components.sorted { breakdown.number(of: $0) < breakdown.number(of: $1) } }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let ordered = self.ordered
            let anchors = ordered.map { anchor(for: $0, in: size) }
            let pins = positions(for: anchors, in: size)
            let selected = ordered.first { $0.id == selectedID }
            ZStack(alignment: .topLeading) {
                if let selected {
                    let box = rect(for: selected, in: size)
                    CornerBrackets()
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(0.45), radius: 4)
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                        .transition(.opacity.combined(with: .scale(scale: 1.08)))
                        .allowsHitTesting(false)
                }
                LeaderLines(segments: leaders(from: anchors, to: pins))
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                GlassEffectContainer(spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, component in
                            if index < revealed {
                                pin(component, at: pins[index])
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                }
                if let selected {
                    // Above the pins, so no other pin covers its text; taps pass through to them.
                    CalloutPlacement(box: rect(for: selected, in: size)) {
                        callout(for: selected)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
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

    private func anchor(for component: Component, in size: CGSize) -> CGPoint {
        let point = component.pinAnchor
        return CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    /// Pin centers: the items' anchors spread apart and kept inside the photo.
    private func positions(for anchors: [CGPoint], in size: CGSize) -> [CGPoint] {
        PinLayout.spread(anchors.map { SIMD2(Double($0.x), Double($0.y)) }, spacing: Double(pinSpacing),
                         in: SIMD2(Double(size.width), Double(size.height)), inset: Double(pinSize / 2 + 2))
            .map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// Leaders for revealed pins that were moved noticeably off their item's anchor.
    private func leaders(from anchors: [CGPoint], to pins: [CGPoint]) -> [LeaderLines.Segment] {
        zip(anchors, pins).prefix(revealed).compactMap { anchor, pin in
            hypot(pin.x - anchor.x, pin.y - anchor.y) > pinSize * 0.6 ? LeaderLines.Segment(from: anchor, to: pin) : nil
        }
    }

    private func level(of component: Component) -> ImpactLevel? {
        ImpactLevel(yearly: breakdown.yearly(filter.shareMetric, of: component)?.value ?? 0, metric: filter.shareMetric)
    }

    private func pin(_ component: Component, at point: CGPoint) -> some View {
        let isSelected = component.id == selectedID
        let number = breakdown.number(of: component)
        return Button { onSelect(component) } label: {
            Text("\(number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: pinSize - 8, height: pinSize - 8)
                .background(Theme.impactTint(level(of: component)).gradient, in: .circle)
                .overlay {
                    if isSelected { Circle().strokeBorder(.white, lineWidth: 2) }
                }
                .padding(4)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID(component.id, in: glass)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .scaleEffect(isSelected ? 1.12 : 1)
        .position(point)
        .accessibilityLabel(accessibilityText(component, number: number))
        .accessibilityIdentifier("hotspot.\(component.name)")
    }

    /// The selected item's name and yearly value: white on a dark backing that stays legible over a white table or
    /// a pale label, which plain glass did not.
    private func callout(for component: Component) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(component.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            if let value = breakdown.yearly(filter.shareMetric, of: component), !value.isEffectivelyZero {
                Text(value.formattedPerYear)
                    .font(.caption2.monospacedDigit())
                    .opacity(0.9)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.68), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.22)))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }

    private func accessibilityText(_ component: Component, number: Int) -> String {
        let metric = filter.shareMetric
        let share = breakdown.share(of: component, metric: metric, in: components)
        let value = breakdown.yearly(metric, of: component).map { "\($0.formattedPerYear), " } ?? ""
        let percent = Int((share * 100).rounded())
        return "\(number). \(component.name), \(value)\(percent)% of \(metric.displayName.lowercased()) per year"
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

/// Places the selected item's callout just above its box, else just below, else inside the top of the box (a box
/// that fills the photo), centered on the box and clamped by its own measured width, so it is never cut off at the
/// photo's edge and does not cover the item when there is room beside it.
private struct CalloutPlacement: Layout {
    let box: CGRect
    var margin: CGFloat = 8
    var gap: CGFloat = 6
    var maxWidth: CGFloat = 260

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let callout = subviews.first else { return }
        let available = max(0, min(maxWidth, bounds.width - 2 * margin))
        let width = min(callout.sizeThatFits(.unspecified).width, available)
        let size = callout.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let x = min(max(box.midX - size.width / 2, margin), max(margin, bounds.width - margin - size.width))
        let above = box.minY - gap - size.height
        let below = box.maxY + gap
        let y: CGFloat
        if above >= margin {
            y = above
        } else if below + size.height <= bounds.height - margin {
            y = below
        } else {
            y = min(max(box.minY + gap, margin), max(margin, bounds.height - margin - size.height))
        }
        callout.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                      proposal: ProposedViewSize(width: size.width, height: size.height))
    }
}

/// Thin lines from items' anchors to the pins the layout moved away from them, each with a small ring at the
/// item's end, so a moved pin still points at its item.
private struct LeaderLines: Shape {
    struct Segment {
        let from: CGPoint
        let to: CGPoint
    }

    var segments: [Segment]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for segment in segments {
            path.addEllipse(in: CGRect(x: segment.from.x - 2.5, y: segment.from.y - 2.5, width: 5, height: 5))
            path.move(to: segment.from)
            path.addLine(to: segment.to)
        }
        return path
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
