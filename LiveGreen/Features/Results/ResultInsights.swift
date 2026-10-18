import Foundation
import GreenCore

/// Derived figures for the results screen: which metrics and items to show, and what their per-year figures
/// assume. Values, shares and ranks come from `ScanBreakdown`, all per year like the headline.
nonisolated enum ResultInsights {
    /// Picker options for a scan: metrics at least one component shows (applies, has a value, not ≈ 0; see
    /// `Component.displayable`). "All" is offered when more than one metric is.
    static func availableFilters(for components: [Component]) -> [ResultMetricFilter] {
        let metrics = ResultMetricFilter.allCases.filter { filter in
            guard let metric = filter.metric else { return false }
            return shows(metric, in: components)
        }
        return metrics.count > 1 ? metrics + [.all] : metrics
    }

    /// True when at least one component has a value worth showing for `metric`.
    static func shows(_ metric: MetricKey, in components: [Component]) -> Bool {
        components.contains { $0.displayable(metric) != nil }
    }

    /// Components that show `filter`'s metric ("All" keeps every component).
    static func components(_ components: [Component], showing filter: ResultMetricFilter) -> [Component] {
        guard let metric = filter.metric else { return components }
        return components.filter { $0.displayable(metric) != nil }
    }

    // MARK: Assumptions

    /// What one item's year assumes, e.g. "2 servings a week", "3 uses a week" or "4-yr life". For electricity, the
    /// hours a day the device is on, unless the figure comes from a product record's own test.
    static func assumptionLabel(for component: Component, metric: MetricKey, breakdown: ScanBreakdown,
                                engine: ImpactEngine) -> String? {
        if metric == .yearlyElectricity {
            return hoursOn(component, engine: engine).map { "\(amount($0)) h a day" }
        }
        switch breakdown.assumptions[component.id] {
        case .servingsPerWeek(let n): return "\(amount(n)) \(n == 1 ? "serving" : "servings") a week"
        case .packsPerWeek(let n): return "\(amount(n)) \(n == 1 ? "pack" : "packs") a week"
        case .usesPerWeek(let n): return "\(amount(n)) \(n == 1 ? "use" : "uses") a week"
        case .lifespan(let years): return "\(amount(years))-yr life"
        case nil: return nil
        }
    }

    /// The assumptions behind a per-year total, e.g. "Assumes 2 servings a week" or "Assumes food 1–2 servings a
    /// week, packaging 2 uses a week, durables last 4–5 years". Nil when there is nothing to say.
    static func assumptionNote(for components: [Component], metric: MetricKey, breakdown: ScanBreakdown,
                               engine: ImpactEngine) -> String? {
        let counted = components.filter { $0.metrics[metric] != nil }
        if metric == .yearlyElectricity {
            let hours = counted.compactMap { hoursOn($0, engine: engine) }
            return hours.isEmpty ? nil : "Assumes \(span(hours)) h a day of use"
        }
        var servings: [Double] = [], packs: [Double] = [], packaging: [Double] = [], care: [Double] = []
        var lifespans: [Double] = []
        for component in counted {
            switch breakdown.assumptions[component.id] {
            case .servingsPerWeek(let n): servings.append(n)
            case .packsPerWeek(let n): packs.append(n)
            case .usesPerWeek(let n) where component.category == .personalCare: care.append(n)
            case .usesPerWeek(let n): packaging.append(n)
            case .lifespan(let years): lifespans.append(years)
            case nil: break
            }
        }
        let groups = [servings.isEmpty && packs.isEmpty, packaging.isEmpty, care.isEmpty, lifespans.isEmpty]
            .filter { !$0 }.count
        // Name each group only when there is more than one.
        func named(_ noun: String, _ text: String) -> String { groups > 1 ? "\(noun) \(text)" : text }
        var parts: [String] = []
        if !servings.isEmpty { parts.append(named("food", "\(span(servings)) \(plural("serving", servings)) a week")) }
        if !packs.isEmpty {
            // Beside servings, "packs" already says it is food.
            let text = "\(span(packs)) \(plural("pack", packs)) a week"
            parts.append(servings.isEmpty ? named("food", text) : text)
        }
        if !packaging.isEmpty {
            parts.append(named("packaging", "\(span(packaging)) \(plural("use", packaging)) a week"))
        }
        if !care.isEmpty { parts.append(named("personal care", "\(span(care)) \(plural("use", care)) a week")) }
        if !lifespans.isEmpty {
            let years = "\(span(lifespans)) \(plural("year", lifespans))"
            if groups > 1 {
                parts.append("durables last \(years)")
            } else {
                parts.append(lifespans.count == 1 ? "it lasts \(years)" : "they last \(years)")
            }
        }
        return parts.isEmpty ? nil : "Assumes " + parts.joined(separator: ", ")
    }

    /// Hours a day an electronic item is on, as the engine uses them now; nil for record-based electricity.
    private static func hoursOn(_ component: Component, engine: ImpactEngine) -> Double? {
        guard component.metrics[.yearlyElectricity].map({ $0.tier != .exactRecord }) ?? false else { return nil }
        return engine.editableUsage(for: component).first { $0.field == .hoursOnPerDay }?.value
    }

    /// "2" or "1–3": the range of values, each with at most one decimal.
    private static func span(_ values: [Double]) -> String {
        guard let low = values.min(), let high = values.max() else { return "" }
        let lowText = amount(low), highText = amount(high)
        return lowText == highText ? lowText : "\(lowText)–\(highText)"
    }

    /// Singular only when every value is exactly one.
    private static func plural(_ noun: String, _ values: [Double]) -> String {
        values.allSatisfy { $0 == 1 } ? noun : noun + "s"
    }

    private static func amount(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension Measured {
    /// The value with "/yr", e.g. "340 lb CO₂e/yr"; kWh/yr already says it.
    var formattedPerYear: String {
        unit == .kilowattHoursPerYear ? formatted : formatted + "/yr"
    }
}
