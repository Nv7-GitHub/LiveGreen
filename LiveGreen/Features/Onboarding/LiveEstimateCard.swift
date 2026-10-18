import SwiftUI
import GreenCore

/// A live, itemized estimate of the user's yearly footprint during onboarding. It updates with every answer,
/// shows how much the last change moved it, highlights the part the current question affects, and explains
/// that effect in a sentence.
struct LiveEstimateCard: View {
    let profile: UserProfile
    let step: OnboardingStep

    @State private var lastTotal: Double?
    @State private var delta: Double = 0

    /// The region is resolved from the ZIP as it is typed, so the baseline follows the location answer.
    private var resolvedProfile: UserProfile {
        var resolved = profile
        resolved.region = USRegionLookup.resolved(profile.region)
        return resolved
    }

    private var estimate: LifestyleEstimate { LifestyleEstimate(profile: resolvedProfile) }

    /// Yearly kg CO2e one more unit of an answer adds to `part` (the modifiers are linear in each answer).
    private func marginalKg(_ part: LifestyleEstimate.Part, _ set: (inout UserProfile, Int) -> Void) -> Double {
        var none = resolvedProfile, one = resolvedProfile
        set(&none, 0)
        set(&one, 1)
        return (LifestyleEstimate(profile: one).kgPerYear[part] ?? 0) - (LifestyleEstimate(profile: none).kgPerYear[part] ?? 0)
    }

    var body: some View {
        let estimate = estimate
        let total = DisplayUnits.tons(kg: estimate.totalKg)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your estimated footprint").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(total.value, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(value: total.value))
                        Text("\(total.unit) CO₂e / yr").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if abs(delta) >= 1 { deltaChip }
            }
            bar(estimate)
            Text(explanation(estimate))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .animation(.snappy, value: estimate)
        .onChange(of: estimate.totalKg, initial: true) { old, new in
            if lastTotal != nil { delta = new - old }
            lastTotal = new
        }
        .onChange(of: step) { delta = 0 }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("liveEstimate")
    }

    private var deltaChip: some View {
        let shown = DisplayUnits.tons(kg: abs(delta))
        let lower = delta < 0
        return Label("\(shown.value, format: .number.precision(.fractionLength(shown.value < 0.1 ? 2 : 1))) \(shown.unit)",
                     systemImage: lower ? "arrow.down" : "arrow.up")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((lower ? Theme.leaf : Theme.warning).gradient, in: .capsule)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel(lower ? "Down \(shown.value) \(shown.unit)" : "Up \(shown.value) \(shown.unit)")
    }

    private func bar(_ estimate: LifestyleEstimate) -> some View {
        let total = max(estimate.totalKg, 1)
        let focus = step.estimatePart
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(LifestyleEstimate.Part.allCases, id: \.self) { part in
                        let share = (estimate.kgPerYear[part] ?? 0) / total
                        Rectangle()
                            .fill(part.color.gradient)
                            .opacity(focus == nil || focus == part ? 1 : 0.3)
                            .frame(width: max(0, (geometry.size.width - 8) * share))
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 10)
            HStack(spacing: 10) {
                ForEach(LifestyleEstimate.Part.allCases, id: \.self) { part in
                    HStack(spacing: 3) {
                        Circle().fill(part.color).frame(width: 6, height: 6)
                        Text(part.shortName).font(.caption2)
                    }
                    .foregroundStyle(focus == nil || focus == part ? .primary : .secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private func explanation(_ estimate: LifestyleEstimate) -> String {
        func amount(_ part: LifestyleEstimate.Part) -> String {
            let tons = DisplayUnits.tons(kg: estimate.kgPerYear[part] ?? 0)
            return "\(tons.value.formatted(.number.precision(.fractionLength(1)))) \(tons.unit)"
        }
        let average = DisplayUnits.tons(kg: estimate.regionAverageKg)
        let averageText = "\(average.value.formatted(.number.precision(.fractionLength(1)))) \(average.unit)"
        switch step {
        case .location:
            return "We start from the average for your area, \(averageText) a year. Each answer adjusts it."
        case .household:
            return "Home energy: \(amount(.homeEnergy)) a year. Sharing a home splits appliances and heating, so more people means less each."
        case .diet:
            let meat = DisplayUnits.carbon(kg: marginalKg(.food) { $0.meatMealsPerWeek = $1; $0.dairyMealsPerWeek = 0 })
            let dairy = DisplayUnits.carbon(kg: marginalKg(.food) { $0.dairyMealsPerWeek = $1; $0.meatMealsPerWeek = 0 })
            return "Food: \(amount(.food)) a year. Each weekly meat meal adds about \(meat) a year; a dairy meal about \(dairy)."
        case .commute:
            let car = DisplayUnits.system == .imperial
                ? "\(Measured.format((LifestyleEstimate.kgPerKm[.car] ?? 0) * 1.609_34 * DisplayUnits.poundsPerKilogram)) lb per mile"
                : "\(Measured.format(LifestyleEstimate.kgPerKm[.car] ?? 0)) kg per km"
            return "Getting around: \(amount(.travel)) a year. A typical car emits about \(car); walking and cycling are zero."
        case .home:
            return "Home energy: \(amount(.homeEnergy)) a year. A bigger home raises it; a heat pump emits less than gas, oil or resistance heat."
        case .clothing:
            let item = DisplayUnits.carbon(kg: marginalKg(.clothing) { $0.newClothesPerYear = Double($1) })
            return "Clothing: \(amount(.clothing)) a year. Each new item a year adds about \(item); second-hand avoids most of it."
        case .chargers:
            return "This doesn't change your estimate. Later, LiveGreen can run these on the cleanest hours with a smart plug."
        }
    }
}

extension OnboardingStep {
    /// The estimate part this question changes.
    var estimatePart: LifestyleEstimate.Part? {
        switch self {
        case .household, .home: .homeEnergy
        case .diet: .food
        case .commute: .travel
        case .clothing: .clothing
        case .location, .chargers: nil
        }
    }
}

extension LifestyleEstimate.Part {
    var shortName: String {
        switch self {
        case .food: "Food"
        case .homeEnergy: "Home"
        case .clothing: "Clothes"
        case .travel: "Travel"
        case .everythingElse: "Other"
        }
    }

    var color: Color {
        switch self {
        case .food: .orange
        case .homeEnergy: .yellow
        case .clothing: .purple
        case .travel: .blue
        case .everythingElse: .gray
        }
    }
}
