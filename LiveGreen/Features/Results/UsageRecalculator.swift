import Foundation
import GreenCore

/// A chip the user picked in the questions sheet.
nonisolated struct QuestionAnswer: Hashable, Sendable {
    let question: PendingQuestion
    let option: AnswerOption
}

/// Local re-run after question answers (spec §5.5): writes each answer into the component's
/// `UsageProfile`, re-derives use-phase figures with the §5.6 formulas and re-sums the totals. No
/// network calls.
///
/// - `yearlyElectricity = (powerOn × hoursOn + standby × standbyHours) × 365 / 1000` when power figures
///   exist; otherwise it is scaled by the change in the answered usage rate.
/// - Carbon moves by the change in use-phase emissions over the item's life:
///   `ΔkWh/yr × grid kg/kWh × lifespan`.
nonisolated struct UsageRecalculator: Sendable {
    /// Grid intensity for the user's region, kg CO₂e per kWh.
    var gridKgPerKWh: Double

    static let answerSource = Source(title: "Your answer in LiveGreen", tier: .factorModel)

    func apply(_ answers: [QuestionAnswer], to result: ScanResult) -> ScanResult {
        var updated = result
        for answer in answers {
            guard let field = answer.option.field, let value = answer.option.value,
                  let index = updated.components.firstIndex(where: { $0.id == answer.question.componentID })
            else { continue }
            updated.components[index] = recompute(updated.components[index], setting: field, to: value)
        }
        updated.totals = ScanTotals.sum(updated.components)
        return updated
    }

    func recompute(_ component: Component, setting field: UsageField, to value: Double) -> Component {
        var updated = component
        let previous = component.usage ?? UsageProfile()
        var usage = previous.setting(field, to: value)
        // Keep on + standby hours covering the day when the fixture assumed they did.
        if field == .hoursOnPerDay, let on = previous.hoursOnPerDay, let standby = previous.standbyHoursPerDay,
           abs(on + standby - 24) < 0.01 {
            usage.standbyHoursPerDay = max(0, 24 - value)
        }
        updated.usage = usage

        guard let oldKWh = component.metrics[.yearlyElectricity],
              let newKWh = yearlyElectricity(component, usage: usage, previous: previous, field: field, old: oldKWh)
        else { return updated }
        updated.metrics[.yearlyElectricity] = newKWh

        if let carbon = component.metrics[.carbon] {
            let years = component.metrics[.lifespan]?.value ?? 1
            let factor = gridKgPerKWh * years
            updated.metrics[.carbon] = Measured(
                value: max(0, carbon.value + (newKWh.value - oldKWh.value) * factor),
                low: max(0, carbon.low + (newKWh.low - oldKWh.low) * factor),
                high: max(0, carbon.high + (newKWh.high - oldKWh.high) * factor),
                unit: carbon.unit,
                tier: max(carbon.tier, newKWh.tier),
                sources: carbon.sources + [Self.answerSource])
        }
        return updated
    }

    private func yearlyElectricity(_ component: Component, usage: UsageProfile, previous: UsageProfile,
                                   field: UsageField, old: Measured) -> Measured? {
        if [.hoursOnPerDay, .standbyHoursPerDay].contains(field), let power = component.metrics[.powerOn] {
            let standby = component.metrics[.standbyPower]
            let hoursOn = usage.hoursOnPerDay ?? 0
            let standbyHours = usage.standbyHoursPerDay ?? 0
            func kWh(_ on: Double, _ idle: Double) -> Double { (on * hoursOn + idle * standbyHours) * 365 / 1000 }
            return Measured(
                value: kWh(power.value, standby?.value ?? 0),
                low: kWh(power.low, standby?.low ?? 0),
                high: kWh(power.high, standby?.high ?? 0),
                unit: .kilowattHoursPerYear,
                tier: max(power.tier, standby?.tier ?? power.tier),
                sources: power.sources + [Self.answerSource])
        }
        // No power rating: scale by the answered rate (hours, charges or uses per period).
        guard [.hoursOnPerDay, .chargesPerWeek, .usesPerWeek].contains(field),
              let before = previous[field], before > 0, let after = usage[field] else { return nil }
        let scaled = old.scaled(by: after / before)
        return Measured(value: scaled.value, low: scaled.low, high: scaled.high, unit: old.unit,
                        tier: old.tier, sources: old.sources + [Self.answerSource])
    }
}

extension UserProfile {
    /// Grid zone keys to try, most specific first.
    nonisolated var gridLookupKeys: [String] {
        [region.gridZone, region.usState.map { "US-\($0)" }, region.countryCode].compactMap { $0 }
    }
}
