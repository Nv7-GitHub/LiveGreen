import SwiftUI
import GreenCore

/// Places a glass label above each anchored component at its projected screen point.
struct ARLabelsOverlay: View {
    let components: [Component]
    let positions: [UUID: CGPoint]
    let onSelect: (Component) -> Void

    /// Vertical lift so the label sits above its 3D pin.
    private let lift: CGFloat = 34

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(components) { component in
                    if let point = positions[component.id] {
                        ARComponentLabel(component: component, carbonShare: carbonShare(of: component)) {
                            onSelect(component)
                        }
                        .fixedSize()
                        .position(x: point.x, y: point.y - lift)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: Set(positions.keys))
    }

    private func carbonShare(of component: Component) -> Double {
        let total = components.compactMap { $0.metrics[.carbon]?.value }.reduce(0, +)
        guard total > 0, let value = component.metrics[.carbon]?.value else { return 0 }
        return value / total
    }
}
