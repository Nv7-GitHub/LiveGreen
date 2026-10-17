import SwiftUI
import GreenCore

/// Country and ZIP / postal code; previews the resolved state and grid zone.
struct LocationStepView: View {
    @Binding var region: Region

    private var resolved: Region { USRegionLookup.resolved(region) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Country", selection: $region.countryCode) {
                ForEach(Countries.all, id: \.code) { country in
                    Text(country.name).tag(country.code)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .glassEffect(.regular.interactive(), in: .capsule)

            TextField(region.countryCode == "US" ? "ZIP code" : "Postal code (optional)", text: postalCode)
                .keyboardType(region.countryCode == "US" ? .numberPad : .numbersAndPunctuation)
                .textContentType(.postalCode)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)

            Label(summary, systemImage: "bolt.horizontal")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
