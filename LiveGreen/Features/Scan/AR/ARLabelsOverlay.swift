import SwiftUI
import GreenCore

/// Places a glass label for each anchored component near its projected pin. Labels are laid out in screen
/// space (`ARLabelPlacement`) so they never cover each other, the top bar or the bottom controls; a label that
/// had to move keeps a leader line to its pin, and a pin whose label does not fit shows a dot (the Items menu
/// still lists it). The selected label is placed first and drawn on top.
struct ARLabelsOverlay: View {
    let components: [Component]
    let positions: [UUID: CGPoint]
    /// Height kept clear at the top: status and navigation bars.
    let topInset: CGFloat
    /// Global y of the top of the bottom controls (the mode picker sits below them); labels stay above it.
    let controlsTop: CGFloat?
    var selectedID: UUID?
    let onSelect: (Component) -> Void

    /// Measured label sizes; a typical size stands in until a label has been measured.
    @State private var sizes: [UUID: CGSize] = [:]
    private static let estimatedSize = CGSize(width: 180, height: 50)

    var body: some View {
        GeometryReader { proxy in
            let frames = ARLabelPlacement.frames(for: items, in: bounds(in: proxy))
            ZStack(alignment: .topLeading) {
                leaders(frames)
                // No blending distance: neighbouring labels stay visibly separate instead of merging.
                GlassEffectContainer(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        ForEach(components) { component in
                            if let frame = frames[component.id] {
                                label(for: component)
                                    .position(x: frame.midX, y: frame.midY)
                                    .zIndex(component.id == selectedID ? 1 : 0)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }
            }
            .animation(.smooth(duration: 0.25), value: Set(frames.keys))
        }
    }

    private func bounds(in proxy: GeometryProxy) -> CGRect {
        // Measured here, inside the safe-area-ignoring overlay: its own frame stops at the tab bar.
        let frame = proxy.frame(in: .global)
        let bottom = controlsTop.map { $0 - frame.minY - 10 } ?? proxy.size.height
        let top = topInset + 6
        return CGRect(x: 8, y: top, width: max(0, proxy.size.width - 16), height: max(0, bottom - top))
    }

    private func label(for component: Component) -> some View {
        ARComponentLabel(component: component, carbonShare: carbonShare(of: component),
                         isSelected: component.id == selectedID) {
            onSelect(component)
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { sizes[component.id] = $0 }
        .accessibilityIdentifier("arLabel.\(component.name)")
    }

    /// Thin lines from each pin to its label, drawn under the labels; skipped when the label sits on its pin.
    private func leaders(_ frames: [UUID: CGRect]) -> some View {
        Path { path in
            for (id, pin) in positions {
                guard let frame = frames[id] else {
                    path.addEllipse(in: CGRect(x: pin.x - 5, y: pin.y - 5, width: 10, height: 10))
                    continue
                }
                let end = ARLabelPlacement.leaderEnd(from: pin, to: frame)
                guard hypot(end.x - pin.x, end.y - pin.y) > 14 else { continue }
                path.move(to: pin)
                path.addLine(to: end)
                path.addEllipse(in: CGRect(x: pin.x - 3, y: pin.y - 3, width: 6, height: 6))
            }
        }
        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .shadow(color: .black.opacity(0.4), radius: 1.5)
        .allowsHitTesting(false)
    }

    private var items: [ARLabelPlacement.Item] {
        components.compactMap { component in
            guard let anchor = positions[component.id] else { return nil }
            return ARLabelPlacement.Item(id: component.id, anchor: anchor,
                                         size: sizes[component.id] ?? Self.estimatedSize,
                                         priority: component.id == selectedID ? 2 : carbonShare(of: component))
        }
    }

    private func carbonShare(of component: Component) -> Double {
        let total = components.compactMap { $0.metrics[.carbon]?.value }.reduce(0, +)
        guard total > 0, let value = component.metrics[.carbon]?.value else { return 0 }
        return value / total
    }
}
