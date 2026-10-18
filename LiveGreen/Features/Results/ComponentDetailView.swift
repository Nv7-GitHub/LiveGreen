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
    /// Called when the user changes a usage field; nil hides the usage editor.
    var onUsageChange: ((UsageField, Double) -> Void)?
    /// The scan the item belongs to and the "Not mine" / "It's mine" handler; nil hides the ownership card.
    var ownership: (result: ScanResult, onChange: (Bool?) -> Void)?
    /// Under the usage editor: where the rate comes from and what else it changes.
    var usageNote: String?
    /// Takes back the quick-details answer that refined the item; nil hides the answer card.
    var onUndoAnswer: (() -> Void)?

    @State private var flowMetric: MetricKey?

    private var flowMetrics: [MetricKey] {
        StageSplit.flowMetrics.filter { component.displayable($0) != nil }
    }

    private var activeFlowMetric: MetricKey? {
        let available = flowMetrics
        if let flowMetric, available.contains(flowMetric) { return flowMetric }
        return available.contains(preferredMetric) ? preferredMetric : available.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if ownershipFirst { ownershipCard }
            if let answer = component.detailAnswer, let onUndoAnswer {
                answerCard(answer, undo: onUndoAnswer)
            }
            if let metric = activeFlowMetric, let measured = component.displayable(metric) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if flowMetrics.count > 1 { flowPicker(selected: metric) }
                        FlowView(component: component, metric: metric, measured: measured)
                    }
                }
            }
            if let onUsageChange {
                UsageEditorCard(component: component, onChange: onUsageChange)
                if let usageNote, !ImpactEngine().editableUsage(for: component).isEmpty {
                    Text(usageNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.top, -8)
                        .accessibilityIdentifier("usageNote")
                }
            }
            if let candidate = component.plugCandidate, let plugAction {
                GlassCard(tint: Theme.mint.opacity(0.2)) {
                    PlugRecommendationCard(component: component, candidate: candidate, onPair: plugAction)
                }
            }
            MetricInspector(component: component)
            if !ownershipFirst { ownershipCard }
        }
    }

    /// Up top when it matters (the item is not counted, or the scan is a store or street scene); for the user's own
    /// things "Not mine" waits at the end, below the numbers.
    private var ownershipFirst: Bool {
        guard let ownership else { return false }
        return !component.isCounted || ownership.result.sceneContext?.asksWhichIsYours == true
    }

    @ViewBuilder private var ownershipCard: some View {
        if let ownership {
            OwnershipCard(component: component, result: ownership.result, onChange: ownership.onChange)
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

    /// The quick-details answer behind the numbers, with a way back to the estimate: one tap on the wrong chip used
    /// to stick for good.
    private func answerCard(_ answer: DetailAnswer, undo: @escaping () -> Void) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Your answer: \(answer.label)", systemImage: "checkmark.bubble")
                        .font(.subheadline.weight(.semibold))
                    Text("These numbers use it in place of the AI's estimate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("undoDetailAnswer")
            }
        }
    }

    private var identityLine: String {
        let ids = component.identifiers
        var parts = [component.category.displayName]
        if let brand = ids.brand { parts.append(brand) }
        if let model = ids.model { parts.append(model) }
        if let gtin = ids.gtin { parts.append("GTIN \(gtin)") }
        // Plain names ("PET plastic", not "pet"); food's own matter is not listed as "food organic".
        if let materials = MaterialNames.summary(ids.materials, category: component.category) {
            parts.append(materials)
        }
        if let basis = component.basisTitle { parts.append(basis) }
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
        case .yearlyElectricity: "Electricity"
        case .waterPollution: "Pollution"
        case .land: "Land"
        default: metric.displayName
        }
    }
}
