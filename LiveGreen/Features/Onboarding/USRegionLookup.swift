import Foundation
import GreenCore

/// Maps a US ZIP code to its state and Electricity Maps grid zone (spec §9: ZIP → grid region + baseline).
nonisolated enum USRegionLookup {
    /// State for a five-digit ZIP, from USPS three-digit prefix ranges.
    static func state(forZIP zip: String) -> String? {
        let digits = zip.trimmingCharacters(in: .whitespaces).prefix(3)
        guard digits.count == 3, let prefix = Int(digits) else { return nil }
        return prefixRanges.first { $0.range.contains(prefix) }?.state
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

    private static let prefixRanges: [(range: ClosedRange<Int>, state: String)] = [
        (6...9, "PR"), (10...27, "MA"), (28...29, "RI"), (30...38, "NH"), (39...49, "ME"), (50...59, "VT"),
        (60...69, "CT"), (70...89, "NJ"), (100...149, "NY"), (150...196, "PA"), (197...199, "DE"),
        (200...205, "DC"), (206...219, "MD"), (220...246, "VA"), (247...268, "WV"), (270...289, "NC"),
        (290...299, "SC"), (300...319, "GA"), (320...349, "FL"), (350...369, "AL"), (370...385, "TN"),
        (386...397, "MS"), (398...399, "GA"), (400...427, "KY"), (430...459, "OH"), (460...479, "IN"),
        (480...499, "MI"), (500...528, "IA"), (530...549, "WI"), (550...567, "MN"), (570...577, "SD"),
        (580...588, "ND"), (590...599, "MT"), (600...629, "IL"), (630...658, "MO"), (660...679, "KS"),
        (680...693, "NE"), (700...714, "LA"), (716...729, "AR"), (730...749, "OK"), (750...799, "TX"),
        (800...816, "CO"), (820...831, "WY"), (832...838, "ID"), (840...847, "UT"), (850...865, "AZ"),
        (870...884, "NM"), (885...885, "TX"), (889...898, "NV"), (900...961, "CA"), (967...968, "HI"),
        (970...979, "OR"), (980...994, "WA"), (995...999, "AK"),
    ]

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
