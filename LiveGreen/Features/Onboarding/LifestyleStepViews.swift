import SwiftUI
import GreenCore

/// Meat and dairy meals in a typical week, with a week of plates that fills as the counts change.
struct DietStepView: View {
    @Binding var profile: UserProfile

    private var average: MealFactors { ReferenceStore.bundled.cohort.meals }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WeekOfMealsArt(meatMeals: profile.meatMealsPerWeek, dairyMeals: profile.dairyMealsPerWeek)
            AnswerSlider(title: "Meat, poultry or fish", icon: "🍗", value: meals(\.meatMealsPerWeek),
                         range: 0...Double(UserProfile.mealsPerWeek), tint: .orange,
                         identifier: "onboarding.meatMeals", valueText: Self.mealsText)
            AnswerSlider(title: "Dairy", icon: "🧀", value: meals(\.dairyMealsPerWeek),
                         range: 0...Double(UserProfile.mealsPerWeek), tint: .yellow,
                         identifier: "onboarding.dairyMeals", valueText: Self.mealsText)
            Text("Count meals where it's an important part, like chicken curry or mac and cheese. That reads as "
                 + "\(profile.diet.profileLabel.lowercased()); a typical US diet has meat in about "
                 + "\(Int(average.averageMeatMealsPerWeek)) meals and dairy in about \(Int(average.averageDairyMealsPerWeek)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func meals(_ keyPath: WritableKeyPath<UserProfile, Int>) -> Binding<Double> {
        Binding(get: { Double(profile[keyPath: keyPath]) },
                set: { profile[keyPath: keyPath] = Int($0.rounded()) })
    }

    static func mealsText(_ value: Double) -> String {
        switch Int(value.rounded()) {
        case 0: "None"
        case UserProfile.mealsPerWeek: "Every meal"
        case 1: "1 meal a week"
        case let count: "\(count) meals a week"
        }
    }
}

/// Home type, rough floor area and every heating source, over a house drawn to scale.
struct HomeStepView: View {
    @Binding var profile: UserProfile

    /// A new home type starts from its typical size, so the slider and house jump to something sensible.
    private var homeType: Binding<HomeType> {
        Binding(get: { profile.homeType }, set: { newValue in
            guard newValue != profile.homeType else { return }
            profile.homeType = newValue
            profile.floorAreaM2 = nil
        })
    }

    /// "No heating" is exclusive: picking it clears the sources, and picking a source clears it.
    private var heating: Binding<Set<HeatingSource>> {
        let shown: Set<HeatingSource> = profile.heatingSources.isEmpty ? [.none] : profile.heatingSources
        return Binding(get: { shown }, set: { newValue in
            let added = newValue.subtracting(shown)
            profile.heatingSources = added.contains(.none) ? [] : newValue.subtracting([.none])
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HouseArt(homeType: profile.homeType, areaM2: profile.shownFloorAreaM2, heating: profile.orderedHeatingSources)
            SingleChoiceChips(selection: homeType)
            FloorAreaSlider(profile: $profile)
            VStack(alignment: .leading, spacing: 2) {
                Text("Heating").font(.subheadline.weight(.semibold))
                Text("Select all that apply; several count equally.").font(.footnote).foregroundStyle(.secondary)
            }
            MultiChoiceChips(selection: heating)
        }
    }
}

/// Approximate floor area, stored in m² and shown in ft² in imperial units, with the typical size for the
/// home type beside it.
private struct FloorAreaSlider: View {
    @Binding var profile: UserProfile

    private var imperial: Bool { DisplayUnits.system == .imperial }
    private var perM2: Double { imperial ? DisplayUnits.squareFeetPerSquareMeter : 1 }

    private var shown: Binding<Double> {
        Binding(get: { profile.shownFloorAreaM2 * perM2 },
                set: { profile.floorAreaM2 = $0 / perM2 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AnswerSlider(title: "Size, roughly", value: shown, range: imperial ? 100...6_000 : 10...560,
                         step: imperial ? 50 : 5, tint: .orange, identifier: "onboarding.floorArea") { _ in
                FloorAreaFormat.text(m2: profile.shownFloorAreaM2)
            }
            Text("A typical \(profile.homeType.profileLabel.lowercased()) is about "
                 + "\(FloorAreaFormat.text(m2: profile.homeType.typicalFloorAreaM2)). Heating and cooling grow with size.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// New clothing items bought a year, over a rail that fills with shirts.
struct ClothingStepView: View {
    @Binding var perYear: Double

    private var average: Double { ReferenceStore.bundled.cohort.clothing.averageNewItemsPerYear }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClothingRackArt(perYear: perYear)
            AnswerSlider(title: "New items a year", value: $perYear, range: 0...150, tint: .purple,
                         identifier: "onboarding.newClothes") { value in
                value < 0.5 ? "None" : "\(Int(value.rounded())) a year"
            }
            Text("\(monthly) The average American buys about \(Int(average)) new garments a year.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var monthly: String {
        switch perYear / 12 {
        case ..<0.5: "Rarely or never."
        case ..<1.5: "About one a month."
        case let perMonth: "About \(Int(perMonth.rounded())) a month."
        }
    }
}

/// A labelled slider whose value reads out live beside its title ("4 meals a week").
struct AnswerSlider: View {
    let title: String
    /// An emoji shown before the title, left out of the spoken label.
    var icon: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var tint: Color = Theme.leaf
    let identifier: String
    let valueText: (Double) -> String

    init(title: String, icon: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1,
         tint: Color = Theme.leaf, identifier: String, valueText: @escaping (Double) -> String) {
        self.title = title
        self.icon = icon
        _value = value
        self.range = range
        self.step = step
        self.tint = tint
        self.identifier = identifier
        self.valueText = valueText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(icon.map { "\($0)  \(title)" } ?? title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(valueText(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
                    .animation(.snappy, value: value)
            }
            Slider(value: $value, in: range, step: step)
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue(valueText(value))
                .accessibilityIdentifier(identifier)
        }
    }
}
