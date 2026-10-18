import SwiftUI
import GreenCore

/// ZIP / postal code and country above a map that flies to them; previews the resolved state and grid zone.
/// The field comes first so it shows without scrolling on small phones, under the header and live estimate.
struct LocationStepView: View {
    @Binding var region: Region
    @FocusState private var postalFocused: Bool

    private var resolved: Region { USRegionLookup.resolved(region) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The whole capsule focuses the field, not only the 22 pt text line inside it.
            TextField(region.countryCode == "US" ? "ZIP code" : "Postal code (optional)", text: postalCode)
                .keyboardType(region.countryCode == "US" ? .numberPad : .numbersAndPunctuation)
                .textContentType(.postalCode)
                .focused($postalFocused)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(.capsule)
                .onTapGesture { postalFocused = true }
                .glassEffect(.regular, in: .capsule)
                .accessibilityIdentifier("onboarding.postalCode")
                .toolbar {
                    // The number pad has no return key; this is the way to put it away besides Next.
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { postalFocused = false }
                            .accessibilityIdentifier("onboarding.keyboardDone")
                    }
                }

            // A menu with a full-width label: a menu-style Picker only took taps on its short text, not the capsule.
            Menu {
                Picker("Country", selection: $region.countryCode) {
                    ForEach(Countries.all, id: \.code) { country in
                        Text(country.name).tag(country.code)
                    }
                }
            } label: {
                HStack {
                    Text(countryName)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(.capsule)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .accessibilityLabel("Country")
            .accessibilityValue(countryName)
            .accessibilityIdentifier("onboarding.country")

            Label(summary, systemImage: "bolt.horizontal")
                .font(.footnote)
                .foregroundStyle(.secondary)

            RegionMap(region: resolved)
        }
    }

    private var countryName: String {
        Countries.all.first { $0.code == region.countryCode }?.name ?? region.countryCode
    }

    private var summary: String {
        if let state = resolved.usState {
            return "\(state) · grid zone \(resolved.gridZone ?? "US")"
        }
        return "Grid zone \(resolved.gridZone ?? region.countryCode)"
    }

    private var postalCode: Binding<String> {
        Binding(get: { region.postalCode ?? "" },
                set: { region.postalCode = $0.isEmpty ? nil : $0 })
    }
}

/// ISO countries sorted by localized name.
enum Countries {
    static let all: [(code: String, name: String)] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        .map { ($0, Locale.current.localizedString(forRegionCode: $0) ?? $0) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
