import SwiftUI
import MapKit
import GreenCore

/// One item's greener swap as something to do: the pick, the nearby place to get it, and numbered steps to tick
/// off. The other swaps and the like-for-like chart sit below, folded away. Items offered exactly the same swaps
/// share a card (`others`), as before.
struct ActionCard: View {
    let component: Component
    var others: [Component] = []
    let alternatives: [Alternative]
    let pick: Alternative?
    var charging: SmartPlugAlternative.ChargingCarbon?
    let plan: ActionPlan?
    let isPlanning: Bool
    let isDone: (ActionStep) -> Bool
    let onToggle: (ActionStep) -> Void
    let onChoosePlace: (NearbyPlace) -> Void
    let onSelect: (Alternative) -> Void
    let onPair: () -> Void

    @State private var showsOptions = false
    @State private var showsImpact = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let pick {
                    if isPlanning && plan == nil {
                        planningPlaceholder
                    } else if let plan {
                        if let place = plan.place { PlaceCard(place: place) }
                        steps(plan)
                        if !plan.otherPlaces.isEmpty { otherPlaces(plan) }
                    }
                    impact(pick)
                } else {
                    Text(others.isEmpty ? "You're keeping this one. Pick a swap below to get a plan."
                                        : "You're keeping these. Pick a swap below to get a plan.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                options
            }
        }
        .animation(.smooth, value: pick?.id)
        .animation(.smooth, value: plan)
        .accessibilityIdentifier("action.card")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: component.category.systemImage)
                Text(([component.name] + others.map(\.name)).joined(separator: ", "))
                    .lineLimit(1)
                if let saving = yearlySaving {
                    Spacer(minLength: 8)
                    Text("−\(saving)/yr")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.leaf)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let pick {
                Text(plan?.headline ?? title(for: pick))
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("action.headline")
                PracticalityTags(practicality: pick.practicality, framing: framing(for: pick))
            } else {
                Text("No swap picked").font(.title3.weight(.bold))
            }
        }
    }

    private func title(for pick: Alternative) -> String {
        pick.kind == .smartPlugScheduling ? "Charge it in the cleanest hours" : "Switch to \(pick.name.lowercased())"
    }

    private func framing(for pick: Alternative) -> PracticalityTags.Framing {
        if pick.kind == .smartPlugScheduling { return .addOn }
        return SwapMath.isDurable(component) ? .replacement : .ongoing
    }

    private var yearlySaving: String? {
        guard let pick, let saving = SwapMath.yearlySaving(.carbon, component: component, alternative: pick),
              saving.value > 0 else { return nil }
        return DisplayUnits.carbon(kg: saving.value * Double(1 + others.count))
    }

    // MARK: - Plan

    private var planningPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Finding where to get it near you…", systemImage: "location.magnifyingglass")
                .font(.subheadline.weight(.medium))
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.15)).frame(height: 18).shimmering()
            }
        }
        .accessibilityIdentifier("action.planning")
    }

    private func steps(_ plan: ActionPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let done = plan.steps.filter(isDone).count
            HStack {
                Text("Your steps").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(done) of \(plan.steps.count) done")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(done == plan.steps.count ? Theme.leaf : .secondary)
            }
            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                Button { onToggle(step) } label: {
                    StepRow(number: index + 1, step: step, done: isDone(step))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("action.step.\(index)")
            }
        }
    }

    private func otherPlaces(_ plan: ActionPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Also nearby").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(plan.otherPlaces) { place in
                        Button { onChoosePlace(place) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.caption.weight(.semibold)).lineLimit(1)
                                if let distance = place.distanceText(metric: DisplayUnits.system == .metric) {
                                    Text(distance).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .disabled(isPlanning)
                    }
                }
            }
        }
    }

    // MARK: - Folded sections

    @ViewBuilder private func impact(_ pick: Alternative) -> some View {
        DisclosureGroup(isExpanded: $showsImpact) {
            VStack(alignment: .leading, spacing: 8) {
                if pick.kind == .product, let note = sameFoodNote {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
                ComparisonChart(component: component, alternative: pick, charging: charging)
            }
            .padding(.top, 6)
        } label: {
            Label("See the impact\(others.isEmpty ? "" : ", per item")", systemImage: "chart.bar.xaxis")
                .font(.subheadline.weight(.medium))
        }
        .tint(Theme.leaf)
    }

    private var options: some View {
        DisclosureGroup(isExpanded: $showsOptions) {
            VStack(spacing: 8) {
                ForEach(alternatives) { alternative in
                    AlternativeRow(component: component, alternative: alternative,
                                   isSelected: alternative.id == pick?.id, itemCount: 1 + others.count,
                                   onSelect: { onSelect(alternative) }, onPair: onPair)
                }
            }
            .padding(.top, 6)
        } label: {
            Label(alternatives.count > 1 ? "\(alternatives.count) swap options" : "Swap option",
                  systemImage: "arrow.triangle.swap")
                .font(.subheadline.weight(.medium))
        }
        .tint(Theme.leaf)
        .accessibilityIdentifier("action.options")
    }

    /// A food swap for a per-pack item covers the same amount of food at the same rate (`Alternative.onBasis`).
    private var sameFoodNote: String? {
        guard FoodServing.isPerPack(component), let basis = component.basisLabel,
              let packs = ImpactEngine().editableUsage(for: component).first(where: { $0.field == .packsPerWeek }) else {
            return nil
        }
        return "Both \(basis), \(UsageField.packsPerWeek.customLabel(packs.value)): the same amount of food."
    }
}

/// A numbered step with a tick when done.
private struct StepRow: View {
    let number: Int
    let step: ActionStep
    let done: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? Theme.leaf : Color.secondary.opacity(0.15)).frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.primary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                if let detail = step.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(done ? [.isButton, .isSelected] : .isButton)
    }
}

/// The chosen place: a small map, its name and distance, and buttons for directions, a call and its website.
struct PlaceCard: View {
    let place: NearbyPlace

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 900)), interactionModes: []) {
                Marker(place.name, systemImage: "leaf.fill", coordinate: coordinate).tint(Theme.leaf)
                UserAnnotation()
            }
            .frame(height: 120)
            .clipShape(.rect(cornerRadius: 16))
            .allowsHitTesting(false)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.headline).accessibilityIdentifier("action.placeName")
                    Text([place.categoryName, place.distanceText(metric: DisplayUnits.system == .metric).map { "\($0) away" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if let address = place.address {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: directions) {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("action.directions")
                    if let phone = place.phone, let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                        Link(destination: url) { Image(systemName: "phone.fill").padding(.horizontal, 4) }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Call \(place.name)")
                    }
                    if let url = place.url {
                        Link(destination: url) { Image(systemName: "safari.fill").padding(.horizontal, 4) }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Website")
                    }
                }
            }
        }
    }

    private func directions() {
        let item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
