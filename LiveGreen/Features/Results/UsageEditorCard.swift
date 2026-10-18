import SwiftUI
import GreenCore

/// Lets the user set how they actually use an item (hours a day, servings or packs a week…) at any time, not only
/// when a question was asked. Each slider covers the field's full range and commits when released.
struct UsageEditorCard: View {
    let component: Component
    let onChange: (UsageField, Double) -> Void

    @State private var drafts: [UsageField: Double] = [:]

    /// The fields that drive this item's numbers, starting from the engine's current values.
    private var current: [(field: UsageField, value: Double)] { ImpactEngine().editableUsage(for: component) }
    private var fields: [UsageField] { current.map(\.field) }

    var body: some View {
        if !fields.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Your usage", systemImage: "slider.horizontal.3").font(.headline)
                    ForEach(fields, id: \.self) { field in
                        row(field)
                    }
                    if let basis = basisNote {
                        Text(basis)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("usageBasis")
                    }
                    Text("Numbers update when you let go of a slider.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("usageEditor")
        }
    }

    private func row(_ field: UsageField) -> some View {
        let value = drafts[field] ?? current.first { $0.field == field }?.value ?? field.customRange.lowerBound
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Self.title(field)).font(.subheadline)
                Spacer()
                Text(field.rateLabel(value))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Slider(value: Binding(get: { value }, set: { drafts[field] = $0 }),
                   in: field.customRange, step: field.customStep) { editing in
                if !editing, let draft = drafts[field] { onChange(field, draft) }
            }
            .tint(Theme.leaf)
            .accessibilityLabel(Self.title(field))
            .accessibilityValue(field.rateLabel(value))
        }
    }

    /// For food, what the item's figures cover and how a year is counted from the slider; for a vehicle, what its
    /// year is made of; for a household consumable, how many it uses up a year; for a seasonal appliance, its season.
    private var basisNote: String? {
        if component.category == .vehicle {
            let years = Int(ImpactEngine().lifespan(of: component).value.rounded())
            return "A year is driving this far, plus making the vehicle spread over \(years) years."
        }
        if let days = ReferenceStore.bundled.deviceProfile(for: component)?.activeDaysPerYear {
            return "Hours on a day it runs, about \(Int(days.rounded())) days a year."
        }
        if component.category == .household, component.quantities.consumable == true {
            let engine = ImpactEngine()
            let uses = Int(engine.usesPerContainer(of: component).rounded())
            let perYear = engine.consumablesPerYear(of: component).formatted(.number.precision(.fractionLength(0...1)))
            return "One lasts about \(uses) uses, so that is \(perYear) a year."
        }
        guard let basis = component.basisTitle else { return nil }
        let unit = FoodServing.isPerPack(component) ? "packs" : "servings"
        return "\(basis). A year is \(unit) a week × 52."
    }

    /// Verb titles for counts read with `rateLabel`: "Used once a week", not "Used 1 uses a week".
    static func title(_ field: UsageField) -> String {
        switch field {
        case .hoursOnPerDay: "In use"
        case .standbyHoursPerDay: "Plugged in, idle"
        case .servingsPerWeek: "Servings"
        case .packsPerWeek: "Packs"
        case .wearsPerYear: "Worn"
        case .usesPerWeek: "Used"
        case .chargesPerWeek: "Charged"
        case .kmPerWeek: "Driven"
        }
    }
}
