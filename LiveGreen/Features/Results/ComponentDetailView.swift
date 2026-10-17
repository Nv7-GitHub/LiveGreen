import SwiftUI
import GreenCore

/// Component detail (spec §6): identity, lifecycle flow for a chosen metric, optional smart-plug
/// recommendation, then the metric inspector. Shown in a detent sheet in portrait and as the side
/// inspector in landscape.
struct ComponentDetailView: View {
    let component: Component
    /// Metric to open the flow on, when the component has it.
    var preferredMetric: MetricKey = .carbon
    /// Shown when the component is a deferrable load and plug features are on.
    var plugAction: (() -> Void)?

    @State private var flowMetric: MetricKey?

    private var flowMetrics: [MetricKey] {
        StageSplit.flowMetrics.filter { component.metrics[$0] != nil }
    }

    private var activeFlowMetric: MetricKey? {
        let available = flowMetrics
        if let flowMetric, available.contains(flowMetric) { return flowMetric }
        return available.contains(preferredMetric) ? preferredMetric : available.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let metric = activeFlowMetric, let measured = component.metrics[metric] {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if flowMetrics.count > 1 { flowPicker(selected: metric) }
                        FlowView(component: component, metric: metric, measured: measured)
                    }
                }
            }
            if let candidate = component.plugCandidate, let plugAction {
                GlassCard(tint: Theme.mint.opacity(0.2)) {
                    PlugRecommendationCard(component: component, candidate: candidate, onPair: plugAction)
                }
            }
            MetricInspector(component: component)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: component.category.systemImage)
                .font(.title2)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.tint(Theme.leaf.opacity(0.3)), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name).font(.title3.weight(.semibold))
                Text(identityLine).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var identityLine: String {
        let ids = component.identifiers
        var parts = [component.category.displayName]
        if let brand = ids.brand { parts.append(brand) }
        if let model = ids.model { parts.append(model) }
        if let gtin = ids.gtin { parts.append("GTIN \(gtin)") }
        if !ids.materials.isEmpty {
            parts.append(ids.materials.map { "\(Int($0.percent))% \($0.material)" }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private func flowPicker(selected: MetricKey) -> some View {
        Picker("Flow metric", selection: Binding(get: { selected }, set: { flowMetric = $0 })) {
            ForEach(flowMetrics, id: \.self) { metric in
                Text(shortName(metric)).tag(metric)
            }
        }
        .pickerStyle(.segmented)
    }

    private func shortName(_ metric: MetricKey) -> String {
        switch metric {
        case .yearlyElectricity: "kWh"
        case .waterPollution: "Pollution"
        case .land: "Land"
        default: metric.displayName
        }
    }
}
