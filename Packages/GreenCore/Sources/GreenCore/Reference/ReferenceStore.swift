import Foundation

/// The bundled reference tables (spec §5.4), loaded from `Resources/ReferenceData/*.json`.
/// Lookups accept free text: keys and aliases are normalized, and multi-word queries fall back to
/// the longest matching alias ("beef burger" → beef).
public struct ReferenceStore: ReferenceProviding {
    /// Tables bundled with GreenCore. Empty only if the bundle is broken (covered by tests).
    public static let bundled: ReferenceStore = (try? ReferenceStore(bundle: .module)) ?? ReferenceStore()

    /// GreenCore's resource bundle (holds `ReferenceData/*.json`).
    public static var resourceBundle: Bundle { .module }

    public static let tableNames = ["food_factors", "fiber_factors", "material_endoflife", "device_defaults",
                                    "grid_intensity", "per_capita", "asus_pcf", "vehicle_factors"]

    let foods: AliasIndex<FoodFactor>
    let fibers: AliasIndex<FiberFactor>
    let materials: AliasIndex<MaterialFactor>
    let devices: AliasIndex<DeviceProfile>
    let grids: [String: RegionalGridIntensity]
    let regions: RegionResolver
    let countryBaselines: [String: PerCapitaBaseline]
    let stateCarbonRatios: [String: Double]
    let asus: [String: ASUSPCFDetail]
    let materialsByResin: [Int: MaterialFactor]

    /// Garment-making overhead and lifespan for the clothing factor model.
    public let garment: GarmentProcessing?
    /// Production, driving and lifespan figures for the vehicle model.
    public let vehicles: VehicleFactors?
    /// Category shares and lifestyle modifiers for the cohort model.
    public let cohort: CohortReference
    /// Provenance of every record, for integrity checks and "unverified" labels.
    public let recordInfo: [ReferenceRecordInfo]

    /// Empty store (no records).
    public init() {
        foods = AliasIndex([]); fibers = AliasIndex([]); materials = AliasIndex([]); devices = AliasIndex([])
        grids = [:]; regions = RegionResolver(); countryBaselines = [:]; stateCarbonRatios = [:]; asus = [:]
        materialsByResin = [:]; garment = nil; vehicles = nil
        cohort = CohortReference(categoryShares: [:], commuteModifiers: [:], citations: [])
        recordInfo = []
    }

    /// Loads the tables from a bundle's `ReferenceData` resources.
    public init(bundle: Bundle) throws {
        var data: [String: Data] = [:]
        for name in Self.tableNames {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "ReferenceData")
                    ?? bundle.url(forResource: name, withExtension: "json") else {
                throw GreenCoreError.decoding("Missing reference table \(name).json")
            }
            data[name] = try Data(contentsOf: url)
        }
        try self.init(tables: data)
    }

    /// Decodes tables from raw JSON keyed by table name (see `tableNames`).
    public init(tables: [String: Data]) throws {
        func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
            guard let data = tables[name] else { throw GreenCoreError.decoding("Missing reference table \(name)") }
            do { return try JSONDecoder().decode(T.self, from: data) } catch {
                throw GreenCoreError.decoding("\(name).json: \(error)")
            }
        }
        var info: [ReferenceRecordInfo] = []

        let food = try decode(RecordsFile<FoodRecordFile>.self, "food_factors").records
        foods = AliasIndex(food.map { ($0.group, $0.aliases, $0.factor) })
        info += food.map { ReferenceRecordInfo(table: "food_factors", key: $0.group, verified: $0.verified, citation: $0.citation) }

        let fiberFile = try decode(FiberFile.self, "fiber_factors")
        fibers = AliasIndex(fiberFile.records.map { ($0.material, $0.aliases, $0.factor) })
        garment = GarmentProcessing(kgCO2ePerKg: fiberFile.processing.kgCO2ePerKg, litersPerKg: fiberFile.processing.litersPerKg,
                                    gPO4ePerKg: fiberFile.processing.gPO4ePerKg, lifespanYears: fiberFile.garmentLifespan.years,
                                    citation: fiberFile.processing.citation, lifespanCitation: fiberFile.garmentLifespan.citation)
        info += fiberFile.records.map { ReferenceRecordInfo(table: "fiber_factors", key: $0.material, verified: $0.verified, citation: $0.citation) }
        info.append(ReferenceRecordInfo(table: "fiber_factors", key: "processing", verified: fiberFile.processing.verified,
                                        citation: fiberFile.processing.citation))
        info.append(ReferenceRecordInfo(table: "fiber_factors", key: "garmentLifespan", verified: fiberFile.garmentLifespan.verified,
                                        citation: fiberFile.garmentLifespan.citation))

        let material = try decode(RecordsFile<MaterialRecordFile>.self, "material_endoflife").records
        materials = AliasIndex(material.map { ($0.material, $0.aliases, $0.factor) })
        var byResin: [Int: MaterialFactor] = [:]
        for record in material { if let code = record.resinCode, byResin[code] == nil { byResin[code] = record.factor } }
        materialsByResin = byResin
        info += material.map { ReferenceRecordInfo(table: "material_endoflife", key: $0.material, verified: $0.verified, citation: $0.citation) }

        let device = try decode(RecordsFile<DeviceRecordFile>.self, "device_defaults").records
        devices = AliasIndex(device.map { ($0.deviceType, $0.aliases, $0.profile) })
        info += device.map { ReferenceRecordInfo(table: "device_defaults", key: $0.deviceType, verified: $0.verified, citation: $0.citation) }

        let vehicleFile = try decode(VehicleFile.self, "vehicle_factors")
        vehicles = vehicleFile.factors
        info += vehicleFile.info

        let grid = try decode(GridFile.self, "grid_intensity")
        var gridMap: [String: RegionalGridIntensity] = [:]
        for record in grid.records {
            let shape = grid.shapes[record.shapeFamily]?.hourly ?? Array(repeating: 1, count: 24)
            gridMap[record.region.uppercased()] = RegionalGridIntensity(
                region: record.region, annualAverageGPerKWh: record.annualAverageGPerKWh, hourlyShape: shape, citation: record.citation)
            info.append(ReferenceRecordInfo(table: "grid_intensity", key: record.region, verified: record.verified, citation: record.citation))
        }
        for (family, shape) in grid.shapes {
            info.append(ReferenceRecordInfo(table: "grid_intensity", key: "shape:\(family)", verified: shape.verified, citation: shape.citation))
        }
        grids = gridMap
        regions = RegionResolver(file: grid)

        let perCapita = try decode(PerCapitaFile.self, "per_capita")
        let built = try PerCapitaBuilder(file: perCapita)
        countryBaselines = built.countries
        stateCarbonRatios = built.stateRatios
        cohort = built.cohort
        info += built.info

        let asusRecords = try decode(RecordsFile<ASUSRecordFile>.self, "asus_pcf").records
        asus = Dictionary(asusRecords.map {
            (ReferenceKey.modelKey($0.model),
             ASUSPCFDetail(record: $0.record, name: $0.name, uncertaintyKgCO2e: $0.uncertaintyKgCO2e, annualKWh: $0.annualKWh))
        }, uniquingKeysWith: { first, _ in first })
        info += asusRecords.map { ReferenceRecordInfo(table: "asus_pcf", key: $0.model, verified: $0.verified, citation: $0.citation) }

        recordInfo = info
    }

    // MARK: ReferenceProviding

    public func foodFactor(group: String) -> FoodFactor? { foods.lookup(group) }
    public func fiberFactor(material: String) -> FiberFactor? { fibers.lookup(material) }
    public func endOfLife(material: String) -> MaterialEndOfLife? { materialFactor(material: material)?.endOfLife }
    public func deviceDefaults(deviceType: String) -> DeviceDefaults? { devices.lookup(deviceType)?.defaults }

    /// eGRID subregion ("NEWE"), Electricity Maps zone ("US-NE-ISNE"), US state as "US-MA", or ISO country code.
    public func gridIntensity(region: String) -> RegionalGridIntensity? {
        let key = region.uppercased().trimmingCharacters(in: .whitespaces)
        if let direct = grids[key] { return direct }
        if let alias = regions.zoneAliases[key], let aliased = grids[alias] { return aliased }
        if key.hasPrefix("US-"), let subregion = regions.stateSubregions[String(key.dropFirst(3))] { return grids[subregion] }
        return nil
    }

    /// ISO country code, or a US state as "US-MA". A bare two-letter code is a country when one exists, else a US state.
    public func perCapita(region: String) -> PerCapitaBaseline? {
        let key = region.uppercased().trimmingCharacters(in: .whitespaces)
        if key.hasPrefix("US-") { return stateBaseline(String(key.dropFirst(3))) }
        return countryBaselines[key] ?? stateBaseline(key)
    }

    /// Exact model, else the longest record model that prefixes the query ("UX3405MA" → UX3405M), else a record
    /// model that the query prefixes (at least 6 characters).
    public func asusPCF(model: String) -> ASUSPCFRecord? { asusDetail(model: model)?.record }

    // MARK: Extended lookups

    public func materialFactor(material: String) -> MaterialFactor? { materials.lookup(material) }
    public func materialFactor(resinCode: Int) -> MaterialFactor? { materialsByResin[resinCode] }
    public func deviceProfile(deviceType: String) -> DeviceProfile? { devices.lookup(deviceType) }

    public func asusDetail(model: String) -> ASUSPCFDetail? {
        let key = ReferenceKey.modelKey(model)
        guard key.count >= 5 else { return nil }
        if let exact = asus[key] { return exact }
        let prefixMatch = asus.keys.filter { key.hasPrefix($0) }.max { $0.count < $1.count }
        if let prefixMatch { return asus[prefixMatch] }
        guard key.count >= 6 else { return nil }
        return asus.keys.filter { $0.hasPrefix(key) }.sorted().first.flatMap { asus[$0] }
    }

    /// At most this many records may share a model line; a line that matches more is too vague to stand for them.
    static let maxASUSLineMatches = 4

    /// Records of one model line, sorted by model, for a laptop recognized by its design rather than a printed model
    /// number: the marketing name has every word of the line and no other line word, apart from an OLED panel
    /// ("Zenbook 14" → the Zenbook 14 and 14 OLED reports, not the Zenbook S 14). Words that do not narrow the line
    /// ("ASUS", "laptop", "inch", a year) are ignored. A line of fewer than two words or without a name word, or one
    /// matching more than `maxASUSLineMatches` records, matches nothing.
    public func asusDetails(modelLine: String) -> [ASUSPCFDetail] {
        func words(_ text: String) -> Set<String> {
            Set(ReferenceKey.normalize(text).split(separator: "_").map(String.init))
        }
        let ignored: Set<String> = ["asus", "laptop", "notebook", "inch", "in", "series", "the"]
        let line = words(modelLine).filter { word in
            !ignored.contains(word) && !(word.count == 4 && word.hasPrefix("20") && word.allSatisfy(\.isNumber))
        }
        guard line.count >= 2, line.contains(where: { $0.contains(where: \.isLetter) }) else { return [] }
        let matches = asus.values.filter { detail in
            let name = words(detail.name)
            let nameLine = name.subtracting(["asus", "oled", detail.record.model.lowercased()])
            return line.isSubset(of: name) && nameLine.isSubset(of: line)
        }.sorted { $0.record.model < $1.record.model }
        return matches.count <= Self.maxASUSLineMatches ? matches : []
    }

    /// Grid intensity for a profile region: grid zone, then ZIP, then US state, then country.
    public func gridIntensity(for region: Region) -> RegionalGridIntensity? {
        if let zone = region.gridZone, let match = gridIntensity(region: zone) { return match }
        if region.countryCode.uppercased() == "US" {
            if let zip = region.postalCode, let subregion = regions.subregion(forZIP: zip), let match = grids[subregion] {
                return match
            }
            if let state = region.usState, let match = gridIntensity(region: "US-\(state)") { return match }
        }
        return gridIntensity(region: region.countryCode) ?? grids["US"]
    }

    /// Per-capita baseline for a profile region: US state (from the state or ZIP), else country, else the US.
    public func perCapita(for region: Region) -> PerCapitaBaseline? {
        if region.countryCode.uppercased() == "US",
           let state = region.usState ?? region.postalCode.flatMap(regions.state(forZIP:)),
           let baseline = stateBaseline(state) {
            return baseline
        }
        return countryBaselines[region.countryCode.uppercased()] ?? countryBaselines["US"]
    }

    /// Two-letter US state for a 5-digit ZIP (or ZIP+4).
    public func usState(forZIP zip: String) -> String? { regions.state(forZIP: zip) }

    /// eGRID subregion for a US ZIP code.
    public func gridSubregion(forZIP zip: String) -> String? { regions.subregion(forZIP: zip) }

    private func stateBaseline(_ state: String) -> PerCapitaBaseline? {
        guard let ratio = stateCarbonRatios[state.uppercased()], var baseline = countryBaselines["US"] else { return nil }
        baseline.region = "US-\(state.uppercased())"
        baseline.medians[.carbon] = (baseline.medians[.carbon] ?? 0) * ratio
        return baseline
    }
}
