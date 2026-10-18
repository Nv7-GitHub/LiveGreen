import SwiftUI
import GreenCore

/// Scan summary (spec §6): the selected metric's yearly total as one big number with its likely range,
/// lifetime and item count as secondary stats, and where the numbers come from. "All" shows every
/// additive total as compact tiles.
struct SummaryHeader: View {
    let result: ScanResult
    let filter: ResultMetricFilter

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                if let metric = filter.metric {
                    singleTotal(metric)
                } else {
                    allTotals
                }
                if let basisNote {
                    Label(basisNote, systemImage: "fork.knife")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("summaryBasis")
                }
                ConfidenceMeter(components: result.components)
            }
        }
    }

    /// Yearly totals saved with the scan; older scans compute them on the fly.
    private var yearlyTotals: [MetricKey: Measured] {
        result.yearlyTotals.isEmpty ? ImpactEngine().yearlyTotals(result.components, seed: result.totalsSeed)
                                    : result.yearlyTotals
    }

    /// Carbon is shown per year (purchase amortized over the item's life, plus use) with lifetime below.
    /// Electricity is already per year. Water, land, plastic and pollution are what it took to make what is
    /// pictured; they are not a yearly cost for durable items.
    private func yearly(_ metric: MetricKey, in totals: [MetricKey: Measured]) -> Measured? {
        metric == .carbon ? totals[metric] : nil
    }

    /// For embodied metrics, the yearly amount from consumables only (food, cups, packaging bought again and
    /// again), or nil when nothing in the scan repeats.
    private func repeatPurchases(_ metric: MetricKey) -> Measured? {
        guard metric != .carbon, metric != .yearlyElectricity else { return nil }
        let engine = ImpactEngine()
        let consumables = result.components.filter {
            if case .unitsPerYear = engine.annualBasis(for: $0) { return $0.displayable(metric) != nil }
            return false
        }
        guard !consumables.isEmpty, let yearly = engine.yearlyTotals(consumables, seed: result.totalsSeed)[metric],
              !yearly.isEffectivelyZero else { return nil }
        return yearly
    }

    /// What the scan's food figures cover (`FoodServing.basis`): barcoded packs of known size count as the whole
    /// pack, other food per serving. Nil without food.
    private var basisNote: String? {
        let food = result.components.filter { $0.category == .food }
        let labels = food.compactMap(\.basisLabel)
        guard let first = labels.first else { return nil }
        if Set(labels).count == 1 { return "Food figures are \(first)" }
        switch food.filter(FoodServing.isPerPack).count {
        case food.count: return "Food figures are per pack"
        case 0: return "Food figures are per serving"
        default: return "Barcoded packs count per pack, other food per serving"
        }
    }

    /// What the per-item total beside the yearly carbon covers: one pack or serving for a single food item, a whole
    /// life when the scan has a durable item, else one of each item pictured.
    private var perItemTitle: String {
        if result.components.count == 1, let basis = FoodServing.basis(of: result.components[0]) {
            if case .pack = basis { return "Per pack" }
            return "Per serving"
        }
        let engine = ImpactEngine()
        let hasDurable = result.components.contains {
            if case .lifetime = engine.annualBasis(for: $0) { return true }
            return false
        }
        return hasDurable ? "Lifetime" : "As pictured"
    }

    /// Totals only for metrics some item shows (see `Component.displayable`), so "0 oz plastic" never appears.
    private func shownTotal(_ metric: MetricKey) -> Measured? {
        guard ResultInsights.shows(metric, in: result.components) else { return nil }
        return result.totals[metric]
    }

    private func headlineTitle(_ metric: MetricKey) -> String {
        switch metric {
        case .carbon: "Carbon per year"
        case .yearlyElectricity: "Electricity per year"
        case .water: "Water to make what's pictured"
        case .land: "Land to make what's pictured"
        case .plasticMass: "Plastic in what's pictured"
        case .waterPollution: "Water pollution from what's pictured"
        default: metric.displayName
        }
    }

    @ViewBuilder private func singleTotal(_ metric: MetricKey) -> some View {
        if let total = shownTotal(metric) {
            let perYear = yearly(metric, in: yearlyTotals)
            let headline = perYear ?? total
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(headlineTitle(metric), systemImage: metric.systemImage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Measured.format(headline.displayValue))
                            .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(headline.displaySymbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("Likely \(headline.formattedRange)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if perYear != nil { stat(perItemTitle, Measured.format(total.displayValue), unit: total.displaySymbol) }
                    if let repeats = repeatPurchases(metric) {
                        stat("Per year, re-buying", Measured.format(repeats.displayValue), unit: repeats.displaySymbol)
                    }
                    stat("Items", "\(ResultInsights.components(result.components, showing: filter).count)", unit: nil)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("summaryTotal")
        } else {
            Label("No \(metric.displayName.lowercased()) figures for these items", systemImage: metric.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, _ value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.headline.monospacedDigit()).contentTransition(.numericText())
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 14))
    }

    private var allTotals: some View {
        let perYear = yearlyTotals
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                         alignment: .leading, spacing: 10) {
            ForEach(ScanTotals.additiveMetrics, id: \.self) { metric in
                if let total = shownTotal(metric) {
                    let shown = yearly(metric, in: perYear) ?? total
                    VStack(alignment: .leading, spacing: 4) {
                        Label(metric.displayName, systemImage: metric.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Measured.format(shown.displayValue)).font(.title3.weight(.bold).monospacedDigit())
                            Text(shown.displaySymbol).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(metric == .carbon || metric == .yearlyElectricity ? "per year" : "as pictured")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.fill.quaternary, in: .rect(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
