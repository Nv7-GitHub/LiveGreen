import SwiftUI
import GreenCore

/// Sankey-style flow (spec §6, feature 1): lifecycle stages on the left flow into the metric's total
/// on the right, with band widths proportional to each stage's share. Drawn in `Canvas`; bands sweep
/// in from the left whenever the metric changes.
struct FlowView: View {
    let component: Component
    let metric: MetricKey
    let measured: Measured

    @State private var progress: CGFloat = 0

    private var split: StageSplit { StageSplit.split(for: component, metric: metric) }

    var body: some View {
        let split = split
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where the \(metric.displayName.lowercased()) comes from")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(measured.formatted).font(.subheadline.monospacedDigit())
            }
            Canvas { context, size in
                SankeyDrawing(split: split, total: measured).draw(in: &context, size: size)
            }
            .frame(height: 236)
            .mask(alignment: .leading) {
                Rectangle().scaleEffect(x: progress, anchor: .leading)
            }
            Text(split.caption(for: component.category))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(split))
        .accessibilityIdentifier("flowView")
        .onAppear(perform: sweep)
        .onChange(of: metric) { sweep() }
    }

    private func sweep() {
        progress = 0
        withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
    }

    private func accessibilitySummary(_ split: StageSplit) -> String {
        // VoiceOver reads "48%" and "<1%" as "48 percent" and "less than 1 percent".
        let parts = split.shares.map { "\($0.stage.displayName) \(StageSplit.percentLabel($0.share))" }
        return "\(metric.displayName) flow: " + parts.joined(separator: ", ")
    }
}

/// Geometry and painting for the flow diagram.
private struct SankeyDrawing {
    let split: StageSplit
    let total: Measured

    private let labelWidth: CGFloat = 104
    private let nodeWidth: CGFloat = 10
    private let minGap: CGFloat = 6
    private let minNodeHeight: CGFloat = 3

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let stages = split.shares
        guard !stages.isEmpty, size.width > labelWidth + 3 * nodeWidth else { return }

        let labels = stages.map { label(for: $0, in: context) }
        let labelHeight = labels.map { $0.name.measure(in: size).height + $0.detail.measure(in: size).height }.max() ?? 0
        let nodes = Self.layout(shares: stages.map(\.share), height: size.height, labelHeight: labelHeight + 6,
                                minGap: minGap, minNodeHeight: minNodeHeight)
        let flowHeight = nodes.reduce(0) { $0 + $1.height }

        let leftX = labelWidth
        let rightX = size.width - nodeWidth
        var rightY = (size.height - flowHeight) / 2

        for (index, part) in stages.enumerated() {
            let node = nodes[index]
            let left = CGRect(x: leftX, y: node.y, width: nodeWidth, height: node.height)
            let right = CGRect(x: rightX, y: rightY, width: nodeWidth, height: node.height)
            let color = part.stage.flowColor

            context.fill(band(from: left, to: right), with: .linearGradient(
                Gradient(colors: [color.opacity(0.55), Theme.leaf.opacity(0.35)]),
                startPoint: CGPoint(x: left.maxX, y: 0), endPoint: CGPoint(x: right.minX, y: 0)))
            context.fill(Path(roundedRect: left, cornerRadius: min(3, node.height / 2)), with: .color(color))
            // Centred on its own node: the layout leaves every node a label's height of room.
            let anchor = CGPoint(x: leftX - 8, y: left.midY)
            context.draw(labels[index].name, at: CGPoint(x: anchor.x, y: anchor.y - 1), anchor: .bottomTrailing)
            context.draw(labels[index].detail, at: CGPoint(x: anchor.x, y: anchor.y + 1), anchor: .topTrailing)

            rightY += node.height
        }

        let totalNode = CGRect(x: rightX, y: (size.height - flowHeight) / 2, width: nodeWidth, height: flowHeight)
        context.fill(Path(roundedRect: totalNode, cornerRadius: 3), with: .color(Theme.leaf))
    }

    /// Each node's top and height. Heights are proportional to the shares (at least `minNodeHeight`), and each node
    /// sits centred in a slot at least `labelHeight` tall, so its label fits beside it, no label is pushed next to
    /// another stage's band, and the column never runs past the canvas.
    static func layout(shares: [Double], height: CGFloat, labelHeight: CGFloat, minGap: CGFloat,
                       minNodeHeight: CGFloat) -> [(y: CGFloat, height: CGFloat)] {
        func nodeHeights(_ scale: CGFloat) -> [CGFloat] { shares.map { max(minNodeHeight, CGFloat($0) * scale) } }
        func slots(_ scale: CGFloat) -> [CGFloat] { nodeHeights(scale).map { max($0 + minGap, labelHeight) } }
        // The largest scale whose slots fit; slots only grow with the scale, so bisect.
        var low: CGFloat = 0, high = height
        for _ in 0..<32 {
            let mid = (low + high) / 2
            if slots(mid).reduce(0, +) <= height { low = mid } else { high = mid }
        }
        let heights = nodeHeights(low)
        var slotHeights = slots(low)
        let used = slotHeights.reduce(0, +)
        if used > height {
            // More stages than labels can fit beside (very large text): squeeze the slots evenly.
            slotHeights = slotHeights.map { $0 * height / used }
        } else {
            // Spread what is left so the column fills the canvas.
            let slack = (height - used) / CGFloat(slotHeights.count)
            slotHeights = slotHeights.map { $0 + slack }
        }
        var top: CGFloat = 0
        return zip(heights, slotHeights).map { nodeHeight, slot in
            defer { top += slot }
            let shown = min(nodeHeight, slot)
            return (top + (slot - shown) / 2, shown)
        }
    }

    /// A ribbon between two node edges, eased with cubic curves.
    private func band(from left: CGRect, to right: CGRect) -> Path {
        let x0 = left.maxX, x1 = right.minX
        let midX = (x0 + x1) / 2
        var path = Path()
        path.move(to: CGPoint(x: x0, y: left.minY))
        path.addCurve(to: CGPoint(x: x1, y: right.minY),
                      control1: CGPoint(x: midX, y: left.minY), control2: CGPoint(x: midX, y: right.minY))
        path.addLine(to: CGPoint(x: x1, y: right.maxY))
        path.addCurve(to: CGPoint(x: x0, y: left.maxY),
                      control1: CGPoint(x: midX, y: right.maxY), control2: CGPoint(x: midX, y: left.maxY))
        path.closeSubpath()
        return path
    }

    /// The stage's name over its value and share, in the header's unit (`Measured.formatted`), so a 0.12 oz CO₂e
    /// item's stages read in ounces too.
    private func label(for part: (stage: LifecycleStage, share: Double),
                       in context: GraphicsContext) -> (name: GraphicsContext.ResolvedText, detail: GraphicsContext.ResolvedText) {
        let scale = total.displayScale
        let value = Measured.format(total.value * scale.factor * part.share, resolution: scale.resolution)
        let name = Text(part.stage.flowLabel).font(.caption2.weight(.semibold))
        let detail = Text("\(value) · \(StageSplit.percentLabel(part.share))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        return (context.resolve(name), context.resolve(detail))
    }
}

extension LifecycleStage {
    var flowColor: Color {
        switch self {
        case .materials: Color(red: 0.72, green: 0.52, blue: 0.30)
        case .manufacturing: .indigo
        case .transport: .teal
        case .use: .yellow
        case .endOfLife: .gray
        }
    }
}
