/// Plain names for the material keys identify and the reference tables use (`material_endoflife.json`), for the
/// item header: "PET plastic" rather than "pet" (the animal), "plastic-lined paperboard" rather than
/// "poly_coated_paperboard". Unknown keys fall back to their words.
public enum MaterialNames {
    static let names: [String: String] = [
        "pet": "PET plastic", "pete": "PET plastic", "pet_thermoform": "PET plastic",
        "hdpe": "HDPE plastic", "ldpe": "LDPE plastic", "pe": "polyethylene", "plastic_film": "plastic film",
        "pp": "polypropylene", "ps": "polystyrene", "eps_foam": "polystyrene foam", "foam": "polystyrene foam",
        "pvc": "PVC", "pla": "PLA bioplastic", "abs": "ABS plastic", "other_plastic": "other plastic",
        "aluminium": "aluminum", "stainless_steel": "stainless steel", "glass_tableware": "glass",
        "corrugated_cardboard": "cardboard", "poly_coated_paperboard": "plastic-lined paperboard",
        "cotton_textile": "cotton", "synthetic_textile": "synthetic fabric", "wool_textile": "wool",
        "lithium_ion_battery": "lithium-ion battery", "li_ion": "lithium-ion battery",
        "electronics_mixed": "electronics", "e_waste": "electronics", "pcb": "circuit boards",
        "detergent_formula": "detergent",
        // The tables' key for biodegradable matter, spelled out so it never reads as an "organic" claim.
        "food_organic": "food or plant matter", "food_waste": "food or plant matter",
    ]

    /// Keys that are a food's own matter, not a material it is made of or packed in.
    static let foodMatter: Set<String> = ["food_organic", "food_waste", "compost"]

    public static func displayName(_ key: String) -> String {
        let normalized = key.lowercased()
        return names[normalized] ?? normalized.replacingOccurrences(of: "_", with: " ")
    }

    /// The header's material line, largest share first: "70% steel, 20% glass, 10% other plastic". For food, its own
    /// matter is left out and the rest is its packaging, named without shares ("Packed in PET plastic"); nil when
    /// nothing is left to say.
    public static func summary(_ materials: [MaterialShare], category: Category) -> String? {
        let sorted = materials.filter { $0.percent > 0 }.sorted { $0.percent > $1.percent }
        if category == .food {
            var seen = Set<String>()
            let packaging = sorted.filter { !foodMatter.contains($0.material.lowercased()) }
                .map { displayName($0.material) }
                .filter { seen.insert($0).inserted }
            return packaging.isEmpty ? nil : "Packed in " + packaging.joined(separator: ", ")
        }
        guard !sorted.isEmpty else { return nil }
        return sorted.map { "\(Int($0.percent.rounded()))% \(displayName($0.material))" }.joined(separator: ", ")
    }
}
