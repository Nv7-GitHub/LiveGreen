/// Maps US ZIP codes and states to eGRID subregions, and Electricity Maps zones to table regions.
struct RegionResolver: Sendable {
    var zoneAliases: [String: String] = [:]
    var stateSubregions: [String: String] = [:]
    private var zipSubregions: [(range: ClosedRange<Int>, subregion: String)] = []
    private var zipStates: [(range: ClosedRange<Int>, state: String)] = []

    init() {}

    init(file: GridFile) {
        zoneAliases = Dictionary(file.zoneAliases.map { ($0.key.uppercased(), $0.value.uppercased()) },
                                 uniquingKeysWith: { first, _ in first })
        stateSubregions = file.stateSubregions
        zipSubregions = file.zip3Subregions.map { ($0.from...$0.to, $0.subregion) }
        zipStates = file.zip3States.map { ($0.from...$0.to, $0.state) }
    }

    func state(forZIP zip: String) -> String? {
        guard let prefix = Self.zip3(zip) else { return nil }
        return zipStates.first { $0.range.contains(prefix) }?.state
    }

    /// ZIP-level override (e.g. NYC vs upstate NY), else the state's dominant subregion.
    func subregion(forZIP zip: String) -> String? {
        guard let prefix = Self.zip3(zip) else { return nil }
        if let override = zipSubregions.first(where: { $0.range.contains(prefix) }) { return override.subregion }
        return state(forZIP: zip).flatMap { stateSubregions[$0] }
    }

    private static func zip3(_ zip: String) -> Int? {
        let digits = zip.prefix { $0.isNumber }
        guard digits.count >= 5 else { return nil }
        return Int(digits.prefix(3))
    }
}
