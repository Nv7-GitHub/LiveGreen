import SwiftUI
import GreenCore

/// Scan summary (spec §6): the selected metric's yearly total as one big number with its likely range, the frequency
/// that year assumes, durables' lifetime and one of each consumable as secondary stats, and where the numbers come
/// from. Every metric uses the same per-year basis as the list below. "All" shows every additive total as tiles.
struct SummaryHeader: View {
    let result: ScanResult
    let filter: ResultMetricFilter
    let breakdown: ScanBreakdown

    private var engine: ImpactEngine { ImpactEngine() }

    /// The counted items the selected metric covers ("All" keeps every counted item). Items the scan leaves out (not
    /// the user's, background, removed) are listed below the totals, never in them.
    private var shown: [Component] { ResultInsights.components(result.totaledComponents, showing: filter) }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                if let metric = filter.metric {
                    singleTotal(metric)
                } else {
                    allTotals
                }
                if let note = ResultInsights.assumptionNote(for: shown, metric: filter.shareMetric,
                                                            breakdown: breakdown, engine: engine) {
                    Label(note, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("summaryBasis")
                }
                ConfidenceMeter(components: shown, metric: filter.shareMetric, breakdown: breakdown)
            }
        }
    }

    /// Yearly totals saved with the scan; older scans compute them on the fly.
    private var yearlyTotals: [MetricKey: Measured] {
        result.yearlyTotals.isEmpty ? engine.yearlyTotals(result.totaledComponents, seed: result.totalsSeed)
                                    : result.yearlyTotals
    }

    /// Yearly totals only for metrics some item shows (see `Component.displayable`), so "0 oz plastic" never appears.
    private func shownYearly(_ metric: MetricKey, in totals: [MetricKey: Measured]) -> Measured? {
        guard ResultInsights.shows(metric, in: result.totaledComponents) else { return nil }
        return totals[metric]
    }

    private func headlineTitle(_ metric: MetricKey) -> String {
        switch metric {
        case .yearlyElectricity: "Electricity per year"
        case .land: "Land per year"
        default: "\(metric.displayName) per year"
        }
    }

    @ViewBuilder private func singleTotal(_ metric: MetricKey) -> some View {
        if let headline = shownYearly(metric, in: yearlyTotals) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(headlineTitle(metric), systemImage: metric.systemImage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(headline.formattedNumber)
                            .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(headline.displayScale.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("Likely \(headline.formattedRange)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    unitTiles(metric)
                    itemsTile
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("summaryTotal")
        } else if result.totaledComponents.isEmpty {
            Label("Nothing here counts toward your footprint. Mark an item as yours to count it.",
                  systemImage: "person.crop.circle.badge.xmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("summaryNothingCounted")
        } else {
            Label("No \(metric.displayName.lowercased()) figures for these items", systemImage: metric.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// How many items the totals cover, and of how many when some are not counted.
    @ViewBuilder private var itemsTile: some View {
        let left = result.notCountedComponents.count
        if left == 0 {
            stat("Items", "\(shown.count)", unit: nil)
        } else {
            stat("Items counted", "\(result.totaledComponents.count)", unit: "of \(result.components.count)")
        }
    }

    /// Per-unit stats beside the yearly headline, kept apart so they never add a durable's whole life to one
    /// serving: durables' lifetime, and one serving, pack or use of each consumable. Electricity is already yearly.
    @ViewBuilder private func unitTiles(_ metric: MetricKey) -> some View {
        if metric != .yearlyElectricity {
            let counted = shown.filter { $0.metrics[metric] != nil }
            let consumables = counted.filter { !breakdown.isDurable($0) }
            let hasDurables = consumables.count < counted.count
            if let lifetime = breakdown.lifetimeTotal(metric, in: counted, seed: result.totalsSeed),
               !lifetime.isEffectivelyZero {
                stat(consumables.isEmpty ? "Lifetime" : "Durables, lifetime",
                     lifetime.formattedNumber, unit: lifetime.displayScale.symbol)
            }
            if let perUnit = breakdown.consumablesTotal(metric, in: counted, seed: result.totalsSeed),
               !perUnit.isEffectivelyZero {
                stat(Self.consumablesTitle(consumables, besideDurables: hasDurables),
                     perUnit.formattedNumber, unit: perUnit.displayScale.symbol)
            }
        }
    }

    /// What the consumables tile covers: one serving or pack of food (`FoodServing.basis`), else one of each item.
    private static func consumablesTitle(_ consumables: [Component], besideDurables: Bool) -> String {
        let isFood = consumables.allSatisfy { $0.category == .food }
        let packs = consumables.filter(FoodServing.isPerPack).count
        let single = consumables.count == 1
        let title = switch (isFood, packs) {
        case (true, 0): single ? "Per serving" : "One serving each"
        case (true, consumables.count): single ? "Per pack" : "One pack each"
        default: single ? "Per item" : "One of each"
        }
        guard besideDurables else { return title }
        return (isFood ? "Food, " : "Consumables, ") + title.lowercased()
    }

    private func stat(_ title: String, _ value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.headline.monospacedDigit()).contentTransition(.numericText())
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
                if let shown = shownYearly(metric, in: perYear) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(metric.displayName, systemImage: metric.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(shown.formattedNumber).font(.title3.weight(.bold).monospacedDigit())
                            Text(shown.displayScale.symbol).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("per year")
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
