/// What drives a vehicle; decides its fuel or electricity per km and the size of its traction battery
/// (`VehicleModel`). Identify reports it from badges and design cues (no grille or tailpipe, a charge port).
public enum Powertrain: String, Codable, Sendable, Hashable, CaseIterable {
    case petrol
    case diesel
    /// A self-charging hybrid (no plug): a small battery, about a third less fuel.
    case hybrid
    case plugInHybrid = "plug_in_hybrid"
    case electric

    /// Accepts the raw values plus common spellings ("gasoline", "EV", "PHEV", "Plug-in hybrid").
    public init?(looseRawValue raw: String) {
        let key = raw.lowercased().filter { $0.isLetter }
        let aliases: [String: Powertrain] = [
            "petrol": .petrol, "gasoline": .petrol, "gas": .petrol, "ice": .petrol, "combustion": .petrol,
            "diesel": .diesel,
            "hybrid": .hybrid, "hev": .hybrid, "mildhybrid": .hybrid, "fullhybrid": .hybrid, "selfcharginghybrid": .hybrid,
            "pluginhybrid": .plugInHybrid, "phev": .plugInHybrid,
            "electric": .electric, "ev": .electric, "bev": .electric, "batteryelectric": .electric,
        ]
        guard let match = aliases[key] else { return nil }
        self = match
    }

    /// Plug-in vehicles charge from the grid, so their driving depends on the user's grid.
    public var plugsIn: Bool { self == .electric || self == .plugInHybrid }
}
