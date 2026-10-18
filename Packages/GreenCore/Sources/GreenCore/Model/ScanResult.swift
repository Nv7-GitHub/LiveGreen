import Foundation

/// How a scan was captured.
public enum ScanMode: String, Codable, Sendable, Hashable, CaseIterable {
    case photo
    case ar
    case barcode

    public var displayName: String {
        switch self {
        case .photo: "Photo"
        case .ar: "Integrated view"
        case .barcode: "Barcode"
        }
    }
}

/// The outcome of one scan (spec §4).
public struct ScanResult: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var date: Date
    public var title: String
    public var mode: ScanMode
    /// JPEG of the captured frame, in the smaller copy kept with the scan (`ScanPhoto`).
    public var photo: Data?
    public var components: [Component]
    /// Per-unit totals of what is pictured: one serving or unit of consumables, whole-life for durables.
    public var totals: [MetricKey: Measured]
    /// The same items over one year (spec §5.6): consumables at their usage, durables ÷ lifespan.
    public var yearlyTotals: [MetricKey: Measured]
    /// Generated greener-setup JPEG/PNG.
    public var greenerImage: Data?
    /// Chosen alternative per component (component id → alternative id).
    public var selectedAlternatives: [UUID: UUID]
    /// Components the user chose to keep as they are, so the default pick is not re-applied (spec §7).
    public var keptOriginals: Set<UUID>
    /// What kind of scene identify saw (the user's own, a store display, a street, a screenshot); nil in scans from
    /// older builds and barcode scans, which count as the user's own.
    public var sceneContext: SceneContext?

    public init(id: UUID = UUID(), date: Date = Date(), title: String, mode: ScanMode = .photo, photo: Data? = nil,
                components: [Component] = [], totals: [MetricKey: Measured] = [:],
                yearlyTotals: [MetricKey: Measured] = [:], greenerImage: Data? = nil,
                selectedAlternatives: [UUID: UUID] = [:], keptOriginals: Set<UUID> = [],
                sceneContext: SceneContext? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.mode = mode
        self.photo = photo
        self.components = components
        self.totals = totals
        self.yearlyTotals = yearlyTotals
        self.greenerImage = greenerImage
        self.selectedAlternatives = selectedAlternatives
        self.keptOriginals = keptOriginals
        self.sceneContext = sceneContext
    }

    /// Scans saved before a field existed decode with its empty default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        title = try container.decode(String.self, forKey: .title)
        mode = try container.decode(ScanMode.self, forKey: .mode)
        photo = try container.decodeIfPresent(Data.self, forKey: .photo)
        components = try container.decode([Component].self, forKey: .components)
        totals = try container.decode([MetricKey: Measured].self, forKey: .totals)
        yearlyTotals = try container.decodeIfPresent([MetricKey: Measured].self, forKey: .yearlyTotals) ?? [:]
        greenerImage = try container.decodeIfPresent(Data.self, forKey: .greenerImage)
        selectedAlternatives = try container.decode([UUID: UUID].self, forKey: .selectedAlternatives)
        keptOriginals = try container.decodeIfPresent(Set<UUID>.self, forKey: .keptOriginals) ?? []
        sceneContext = try container.decodeIfPresent(SceneContext.self, forKey: .sceneContext)
    }

    /// Seed for the scan totals: from what was scanned, so a rescan of the same items gives the same ranges.
    public var totalsSeed: UInt64 { StableHash.seed(components) }

    /// Recomputes both totals from the components the results add up (`totaledComponents`): items the user marked
    /// as not theirs, other people's things and background items stay out.
    public mutating func updateTotals(engine: ImpactEngine) {
        totals = engine.itemTotals(totaledComponents, seed: totalsSeed)
        yearlyTotals = engine.yearlyTotals(totaledComponents, seed: totalsSeed)
    }

    /// Monte Carlo seed derived from the scan id so results are reproducible (spec §5.6).
    public var seed: UInt64 {
        withUnsafeBytes(of: id.uuid) { raw in
            raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self) ^ raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
        }
    }

    public func component(withID id: UUID) -> Component? {
        components.first { $0.id == id }
    }
}
