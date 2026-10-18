import SwiftUI
import GreenCore

/// Glass inspector (spec §6, feature 2): every metric the component shows (`Component.displayable`: it
/// applies, has a value and is not ≈ 0) as a `Measured` row, so mixed tiers are visible side by side.
struct MetricInspector: View {
    let component: Component

    var body: some View {
        let metrics = component.displayableMetrics
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                // The legend sits beside the title, clear of the sheet's Done button at the trailing edge.
                HStack(spacing: 10) {
                    Text("Inspector").font(.headline)
                    TierLegend()
                    Spacer(minLength: 0)
                }
                ForEach(metrics, id: \.self) { metric in
                    if let measured = component.displayable(metric) {
                        MeasuredRow(metric: metric, measured: measured, breakdown: breakdown(for: metric))
                    }
                    if metric != metrics.last { Divider() }
                }
            }
        }
        .accessibilityIdentifier("metricInspector")
    }

    private func breakdown(for metric: MetricKey) -> [MeasuredBreakdown] {
        switch metric {
        case .carbon: MeasuredBreakdown.carbon(of: component, engine: ImpactEngine())
        case .plasticMass: MeasuredBreakdown.plastic(of: component)
        default: []
        }
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
