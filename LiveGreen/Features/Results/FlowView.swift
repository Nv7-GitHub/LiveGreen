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
            Text(split.isRecorded ? "Stage split from the product's own record."
                                  : "Typical stage split for \(component.category.displayName.lowercased()) items.")
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
        let parts = split.shares.map { "\($0.stage.displayName) \(Int(($0.share * 100).rounded())) percent" }
        return "\(metric.displayName) flow: " + parts.joined(separator: ", ")
    }
}

/// Geometry and painting for the flow diagram.
private struct SankeyDrawing {
    let split: StageSplit
    let total: Measured

    private let labelWidth: CGFloat = 104
    private let nodeWidth: CGFloat = 10
    private let gap: CGFloat = 10
    private let minNodeHeight: CGFloat = 3

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let stages = split.shares
        guard !stages.isEmpty, size.width > labelWidth + 3 * nodeWidth else { return }

        let gaps = gap * CGFloat(stages.count - 1)
        let usable = max(size.height - gaps, CGFloat(stages.count) * minNodeHeight)
        let heights: [CGFloat] = stages.map { max(minNodeHeight, usable * CGFloat($0.share)) }
        let flowHeight = heights.reduce(0, +)

        let leftX = labelWidth
        let rightX = size.width - nodeWidth
        var leftY: CGFloat = 0
        var rightY = (size.height - flowHeight) / 2
        let labelYs = labelPositions(heights: heights, height: size.height)

        for (index, part) in stages.enumerated() {
            let height = heights[index]
            let left = CGRect(x: leftX, y: leftY, width: nodeWidth, height: height)
            let right = CGRect(x: rightX, y: rightY, width: nodeWidth, height: height)
            let color = part.stage.flowColor

            context.fill(band(from: left, to: right), with: .linearGradient(
                Gradient(colors: [color.opacity(0.55), Theme.leaf.opacity(0.35)]),
                startPoint: CGPoint(x: left.maxX, y: 0), endPoint: CGPoint(x: right.minX, y: 0)))
            context.fill(Path(roundedRect: left, cornerRadius: 3), with: .color(color))
            drawLabel(part, at: CGPoint(x: leftX - 8, y: labelYs[index]), in: &context)

            leftY += height + gap
            rightY += height
        }

        let totalNode = CGRect(x: rightX, y: (size.height - flowHeight) / 2, width: nodeWidth, height: flowHeight)
        context.fill(Path(roundedRect: totalNode, cornerRadius: 3), with: .color(Theme.leaf))
    }

    /// Label centers next to each node, pushed apart so two-line labels never overlap.
    private func labelPositions(heights: [CGFloat], height: CGFloat) -> [CGFloat] {
        let spacing: CGFloat = 35
        var y: CGFloat = 0
        var mids = heights.map { h -> CGFloat in
            defer { y += h + gap }
            return y + h / 2
        }
        for index in mids.indices.dropFirst() {
            mids[index] = max(mids[index], mids[index - 1] + spacing)
        }
        let overflow = (mids.last ?? 0) - (height - spacing / 2)
        if overflow > 0 {
            mids[mids.count - 1] -= overflow
            for index in mids.indices.dropLast().reversed() {
                mids[index] = min(mids[index], mids[index + 1] - spacing)
            }
        }
        return mids.map { max($0, spacing / 2) }
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

    private func drawLabel(_ part: (stage: LifecycleStage, share: Double), at point: CGPoint,
                           in context: inout GraphicsContext) {
        // The header's unit (`Measured.formatted`), so a 0.12 oz CO₂e item's stages read in ounces too.
        let scale = total.displayScale
        let value = Measured.format(total.value * scale.factor * part.share, resolution: scale.resolution)
        let name = Text(part.stage.flowLabel).font(.caption2.weight(.semibold))
        let detail = Text("\(value) · \(Int((part.share * 100).rounded()))%")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        context.draw(context.resolve(name), at: CGPoint(x: point.x, y: point.y - 1), anchor: .bottomTrailing)
        context.draw(context.resolve(detail), at: CGPoint(x: point.x, y: point.y + 1), anchor: .topTrailing)
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
