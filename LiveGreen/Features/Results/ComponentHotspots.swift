import SwiftUI
import GreenCore

/// Glass rounded rectangles over each component's box (spec §6). The tint shows the component's share
/// of the selected metric (carbon for "All"); a `GlassEffectContainer` lets the hotspots grow out of
/// small seeds and morph together as they appear. Overlay this on a `ResultPhoto`.
struct ComponentHotspots: View {
    let components: [Component]
    let filter: ResultMetricFilter
    let selectedID: Component.ID?
    let onSelect: (Component) -> Void

    @State private var revealed = 0
    @Namespace private var glass

    private let seedSize: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            GlassEffectContainer(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
                        hotspot(component, isShown: index < revealed, in: geometry.size)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
        .task(id: components.map(\.id)) { await reveal() }
    }

    private func hotspot(_ component: Component, isShown: Bool, in size: CGSize) -> some View {
        let box = component.boundingBox.clamped
        let rect = CGRect(x: box.x * size.width, y: box.y * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        let share = ResultInsights.share(of: component, metric: filter.shareMetric, in: components)
        let isSelected = component.id == selectedID
        let shape = RoundedRectangle(cornerRadius: Theme.hotspotCornerRadius)

        return Button {
            onSelect(component)
        } label: {
            label(for: component, width: rect.width)
                .opacity(isShown ? 1 : 0)
                .frame(width: isShown ? rect.width : seedSize, height: isShown ? rect.height : seedSize,
                       alignment: .topLeading)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.carbonShareTint(share).opacity(isSelected ? 0.55 : 0.3)).interactive(),
                     in: shape)
        .overlay {
            if isSelected { shape.strokeBorder(.white.opacity(0.9), lineWidth: 2) }
        }
        .glassEffectID(component.id, in: glass)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel(accessibilityText(component, share: share))
        .accessibilityIdentifier("hotspot.\(component.name)")
    }

    private func label(for component: Component, width: CGFloat) -> some View {
        let value = filter.metric.flatMap { component.metrics[$0] } ?? component.metrics[.carbon]
        return VStack(alignment: .leading, spacing: 1) {
            if width > 110 {
                Text(component.name).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            if let value {
                Text(value.formatted).font(.caption2.monospacedDigit()).lineLimit(1)
            }
        }
        // Small boxes shrink the text rather than spilling past the glass.
        .minimumScaleFactor(0.6)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 2)
        .padding(width < 70 ? 4 : 6)
        .frame(width: max(width, seedSize), alignment: .leading)
    }

    private func accessibilityText(_ component: Component, share: Double) -> String {
        "\(component.name), \(Int((share * 100).rounded()))% of \(filter.shareMetric.displayName.lowercased())"
    }

    /// Grows hotspots one after another so the container morphs them into place.
    private func reveal() async {
        revealed = 0
        for index in 1...max(components.count, 1) {
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.bouncy(duration: 0.5)) { revealed = index }
        }
    }
}
