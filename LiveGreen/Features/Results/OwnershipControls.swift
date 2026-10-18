import SwiftUI
import GreenCore

/// Wording for whose items a scan shows (C2, C3): why an item is not counted, and what the scene banner says.
nonisolated enum OwnershipText {
    /// Why the results leave an item out, e.g. "Probably not yours"; nil when it counts.
    static func reason(for component: Component, in result: ScanResult) -> String? {
        guard !result.isTotaled(component) else { return nil }
        if component.markedOwned == false { return "Marked not yours" }
        switch component.exclusion {
        case .background: return "In the background"
        case .onScreen: return "Seen on screen"
        case .notOwned, nil: return "Probably not yours"
        }
    }

    /// The banner over a scan whose items are not all the user's own; nil for an ordinary scan of their things.
    static func banner(for result: ScanResult) -> (title: String, message: String, systemImage: String)? {
        switch result.sceneContext {
        case .storeDisplay:
            return ("Store display", "Only items you mark as yours count toward this scan and your footprint.", "cart")
        case .street:
            return ("Street scene", "Other people's things are left out. Only items you mark as yours count.", "car")
        case .screenshot:
            return ("Seen on screen", "This looks like a screenshot, so nothing here is added to your footprint. "
                + "Numbers show what each item would add per year if you bought it.", "iphone")
        case .own, nil:
            return nil
        }
    }
}

/// The detail sheet's ownership control: "Not mine" for a counted item, "It's mine" to count one the scan left out.
/// In a screenshot an item can also be removed, or counted as bought.
struct OwnershipCard: View {
    let component: Component
    let result: ScanResult
    /// The user's answer: true counts the item, false removes it, nil goes back to the scan's guess.
    let onChange: (Bool?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCounted ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark")
                .font(.title3)
                .foregroundStyle(isCounted ? Theme.leaf : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            actions
        }
        .glassCard(cornerRadius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ownershipCard")
    }

    private var isCounted: Bool { component.isCounted }

    private var title: String {
        if isCounted { return "Counted as yours" }
        return OwnershipText.reason(for: component, in: result) ?? "Not counted"
    }

    private var subtitle: String {
        if isCounted { return "Part of this scan's totals and your footprint." }
        if result.isTotaled(component) { return "Shown as if you bought it; not in your footprint." }
        return "Left out of this scan's totals and your footprint."
    }

    @ViewBuilder private var actions: some View {
        if isCounted {
            Button("Not mine", systemImage: "minus.circle") { onChange(false) }
                .buttonStyle(.glass)
                .accessibilityIdentifier("ownership.notMine")
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                Button(result.isScreenshot ? "I bought it" : "It's mine", systemImage: "plus.circle") { onChange(true) }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("ownership.mine")
                if result.isTotaled(component) {
                    Button("Remove", systemImage: "minus.circle") { onChange(false) }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("ownership.remove")
                }
            }
        }
    }
}

/// "Which is yours?" for a store display or street scan: every item with a check, preselected from identify's guess.
/// Only the checked items count; "None of these" leaves them all out. Swiping it away keeps the guess for now, and
/// the results banner offers it again.
struct WhichIsYoursSheet: View {
    let result: ScanResult
    let onDone: (Set<UUID>) -> Void

    @State private var selected: Set<UUID>

    init(result: ScanResult, onDone: @escaping (Set<UUID>) -> Void) {
        self.result = result
        self.onDone = onDone
        _selected = State(initialValue: Set(result.components.filter(\.isCounted).map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(result.components) { row($0) }
                } header: {
                    Text(explanation).textCase(nil)
                } footer: {
                    Button("None of these are mine") { onDone([]) }
                        .font(.subheadline)
                        .padding(.top, 8)
                        .accessibilityIdentifier("ownershipNone")
                }
            }
            .navigationTitle("Which is yours?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { onDone(selected) }
                        .accessibilityIdentifier("ownershipDone")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("whichIsYours")
    }

    private var explanation: String {
        let place = result.sceneContext == .street ? "a street scene" : "a store display"
        return "This looks like \(place). Only the items you check count toward your footprint; the rest stay listed "
            + "as not counted."
    }

    private func row(_ component: Component) -> some View {
        let isSelected = selected.contains(component.id)
        return Button {
            withAnimation(.snappy) {
                if isSelected { selected.remove(component.id) } else { selected.insert(component.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: component.category.systemImage)
                    .frame(width: 28)
                    .foregroundStyle(.secondary)
                Text(component.name).foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.leaf : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("ownership.\(component.name)")
    }
}

/// Says whose items a store, street or screenshot scan shows, with "Which is yours?" for store and street scenes.
struct SceneBanner: View {
    let result: ScanResult
    var onChooseItems: (() -> Void)?

    var body: some View {
        if let banner = OwnershipText.banner(for: result) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: banner.systemImage)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(banner.title).font(.subheadline.weight(.semibold))
                    Text(banner.message).font(.caption).foregroundStyle(.secondary)
                    if let onChooseItems, result.sceneContext?.asksWhichIsYours == true {
                        Button("Which is yours?", systemImage: "checklist", action: onChooseItems)
                            .font(.subheadline.weight(.medium))
                            .buttonStyle(.glass)
                            .padding(.top, 2)
                            .accessibilityIdentifier("chooseOwnedItems")
                    }
                }
                Spacer(minLength: 0)
            }
            .glassCard(cornerRadius: 20, tint: Theme.mint.opacity(0.18))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sceneBanner")
        }
    }
}
