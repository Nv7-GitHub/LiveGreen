import SwiftUI
import GreenCore

/// Glass inspector (spec §6, feature 2): every metric applicable to the component's category as a
/// `Measured` row, so mixed tiers are visible side by side.
struct MetricInspector: View {
    let component: Component

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Inspector").font(.headline)
                    Spacer()
                    TierLegend()
                }
                ForEach(component.category.applicableMetrics, id: \.self) { metric in
                    MeasuredRow(metric: metric, measured: component.metrics[metric], breakdown: breakdown(for: metric))
                    if metric != component.category.applicableMetrics.last { Divider() }
                }
            }
        }
        .accessibilityIdentifier("metricInspector")
    }

    private func breakdown(for metric: MetricKey) -> [MeasuredBreakdown] {
        metric == .plasticMass ? MeasuredBreakdown.plastic(of: component) : []
    }
}

/// Compact T1–T4 key.
private struct TierLegend: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Tier.allCases, id: \.self) { TierBadge(tier: $0) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tiers: exact record, researched spec, factor model, estimate")
    }
}
