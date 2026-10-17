import Foundation
import GreenCore

/// Maps a US ZIP code to its state and Electricity Maps grid zone (spec §9: ZIP → grid region + baseline).
nonisolated enum USRegionLookup {
    /// State for a five-digit ZIP, from the bundled ZIP3 table.
    static func state(forZIP zip: String) -> String? {
        ReferenceStore.bundled.usState(forZIP: zip.trimmingCharacters(in: .whitespaces))
    }

    /// Electricity Maps zone covering most of a state's load.
    static func gridZone(forState state: String) -> String? {
        zoneByState[state.uppercased()]
    }

    /// Fills state and grid zone from the postal code (US) or the country code (elsewhere).
    static func resolved(_ region: Region) -> Region {
        var region = region
        region.countryCode = region.countryCode.uppercased()
        guard region.countryCode == "US" else {
            region.usState = nil
            region.gridZone = region.countryCode
            return region
        }
        if let zip = region.postalCode, let state = state(forZIP: zip) {
            region.usState = state
        }
        region.gridZone = region.usState.flatMap(gridZone(forState:)) ?? "US"
        return region
    }

    private static let zoneByState: [String: String] = {
        let groups: [String: [String]] = [
            "US-NE-ISNE": ["MA", "RI", "NH", "ME", "VT", "CT"],
            "US-NY-NYIS": ["NY"],
            "US-MIDA-PJM": ["NJ", "PA", "DE", "DC", "MD", "VA", "WV", "OH"],
            "US-CAR-DUK": ["NC", "SC"],
            "US-SE-SOCO": ["GA", "AL", "MS"],
            "US-FLA-FPL": ["FL"],
            "US-TEN-TVA": ["TN", "KY"],
            "US-MIDW-MISO": ["MI", "IN", "IL", "WI", "MN", "IA", "MO", "LA", "AR", "ND"],
            "US-CENT-SWPP": ["KS", "OK", "NE", "SD"],
            "US-TEX-ERCO": ["TX"],
            "US-NW-PSCO": ["CO"],
            "US-NW-PACE": ["WY", "UT"],
            "US-NW-BPAT": ["ID", "OR", "WA", "MT"],
            "US-NW-NEVP": ["NV"],
            "US-SW-AZPS": ["AZ"],
            "US-SW-PNM": ["NM"],
            "US-CAL-CISO": ["CA"],
            "US-HI": ["HI"],
            "US-AK": ["AK"],
        ]
        return groups.reduce(into: [:]) { result, entry in
            for state in entry.value { result[state] = entry.key }
        }
    }()
}
