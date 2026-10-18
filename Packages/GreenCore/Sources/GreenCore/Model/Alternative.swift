import Foundation

/// A greener swap for a component (spec §7). Resolved through the same ladder as originals.
public struct Alternative: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        /// A different product.
        case product
        /// "Shelly smart plug + green-hours scheduling", added locally for deferrable loads.
        case smartPlugScheduling
    }

    /// Whether the swap is bought new or second-hand. A second-hand item was made once already, so it carries only
    /// part of a new one's production impacts (`productionShare`); its use, plastic and lifespan are the item's own.
    public enum Condition: String, Codable, Sendable, Hashable, CaseIterable {
        case new
        case used
        case refurbished

        /// Share of a new item's production impacts (embodied carbon, water, land, water pollution) a second-hand
        /// one is charged: cleaning and transport for a used item, plus parts and testing for a refurbished one.
        /// Nil for a new item.
        public var productionShare: Double? {
            switch self {
            case .new: nil
            case .used: 0.2
            case .refurbished: 0.3
            }
        }

        /// The condition a swap's name states ("Buy a used SUV", "Refurbished monitor"), for suggesters that leave
        /// it out; new when the name says nothing. "Used" counts only as "used X", "a used X" or "buy used", so
        /// "AC used an hour less" stays new.
        public init(name: String) {
            let lowered = name.lowercased()
            let words = lowered.split { !$0.isLetter }.map(String.init)
            let usedPosition = words.firstIndex(of: "used")
            let saysUsed = usedPosition.map { $0 == 0 || ["a", "an", "buy"].contains(words[$0 - 1]) } ?? false
            if words.contains("refurbished") || words.contains("renewed") {
                self = .refurbished
            } else if saysUsed || words.contains("secondhand") || words.contains("thrifted")
                        || lowered.contains("second-hand") || lowered.contains("pre-owned") || lowered.contains("preowned") {
                self = .used
            } else {
                self = .new
            }
        }
    }

    public let id: UUID
    public var kind: Kind
    public var name: String
    public var category: Category
    public var identifiers: Identifiers
    public var quantities: Quantities
    public var usage: UsageProfile?
    public var rationale: String
    public var practicality: Practicality
    public var metrics: [MetricKey: Measured]
    public var fallbackEstimates: [MetricKey: EstimateRange]
    /// New, used or refurbished; `.new` in swaps saved by older builds.
    public var condition: Condition
    /// A durable item used again and again in place of single-use ones (a steel tumbler for paper cups). It is
    /// scored as a household item over its life, with washing for every use; false in swaps saved by older builds.
    public var isReusable: Bool
    /// Years the swap is kept when that differs from the original (a laptop kept longer, a product built to last);
    /// nil to compare it over the original's lifespan.
    public var lifespanYears: Double?
    /// The suggester's judgement of whether a photo of the swap in place would look clearly different from the
    /// original; nil in swaps saved by older builds and from suggesters that do not say (`changesTheLook`).
    public var looksDifferent: Bool?

    public init(id: UUID = UUID(), kind: Kind = .product, name: String, category: Category,
                identifiers: Identifiers = Identifiers(), quantities: Quantities = Quantities(),
                usage: UsageProfile? = nil, rationale: String, practicality: Practicality = Practicality(),
                metrics: [MetricKey: Measured] = [:], fallbackEstimates: [MetricKey: EstimateRange] = [:],
                condition: Condition = .new, isReusable: Bool = false, lifespanYears: Double? = nil,
                looksDifferent: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.category = category
        self.identifiers = identifiers
        self.quantities = quantities
        self.usage = usage
        self.rationale = rationale
        self.practicality = practicality
        self.metrics = metrics
        self.fallbackEstimates = fallbackEstimates
        self.condition = condition
        self.isReusable = isReusable
        self.lifespanYears = lifespanYears
        self.looksDifferent = looksDifferent
    }

    /// Swaps saved before `condition`, `isReusable`, `lifespanYears` and `looksDifferent` existed decode as new,
    /// single-use, on the original's lifespan and with no judgement of their look.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(Category.self, forKey: .category)
        identifiers = try container.decode(Identifiers.self, forKey: .identifiers)
        quantities = try container.decode(Quantities.self, forKey: .quantities)
        usage = try container.decodeIfPresent(UsageProfile.self, forKey: .usage)
        rationale = try container.decode(String.self, forKey: .rationale)
        practicality = try container.decode(Practicality.self, forKey: .practicality)
        metrics = try container.decode([MetricKey: Measured].self, forKey: .metrics)
        fallbackEstimates = try container.decode([MetricKey: EstimateRange].self, forKey: .fallbackEstimates)
        condition = try container.decodeIfPresent(Condition.self, forKey: .condition) ?? .new
        isReusable = try container.decodeIfPresent(Bool.self, forKey: .isReusable) ?? false
        lifespanYears = try container.decodeIfPresent(Double.self, forKey: .lifespanYears)
        looksDifferent = try container.decodeIfPresent(Bool.self, forKey: .looksDifferent)
    }

    /// The category a swap is scored in. A reusable given as packaging or personal care is a durable household
    /// item: spread over its life, not counted again for every use (a jar read as packaging would be 156 jars a
    /// year at 3 uses a week).
    public static func scoredCategory(_ stated: Category, isReusable: Bool) -> Category {
        isReusable && (stated == .packaging || stated == .personalCare) ? .household : stated
    }

    /// Whether taking the swap means buying something: a used or refurbished item, a "Buy …" swap or the smart plug.
    /// Keeping, repairing or using what you have differently is not. For an item the user already owns, a purchase
    /// is never "saves money" next to keeping it, only next to buying a new one.
    public var isPurchase: Bool {
        kind == .smartPlugScheduling || condition != .new || name.lowercased().hasPrefix("buy ")
    }

    /// Whether the swap would show in a photo of the scene, so the greener picture has something to draw (G2): the
    /// suggester's judgement when it gave one; otherwise not for the smart plug, a second-hand copy of the same kind of
    /// item (a used car looks like the car) or a change in how something is used ("Keep it two more years").
    public var changesTheLook: Bool {
        if kind == .smartPlugScheduling { return false }
        if let looksDifferent { return looksDifferent }
        if condition != .new { return false }
        let lowered = name.lowercased()
        return !Self.behaviourPrefixes.contains { lowered.hasPrefix($0) }
    }

    /// How swaps that change a habit rather than an object start.
    static let behaviourPrefixes = ["keep ", "repair", "fix ", "line-dry", "line dry", "air-dry", "air dry", "unplug",
                                    "turn ", "run ", "wash ", "set ", "lower ", "use less", "use it", "share "]

    // MARK: - Safety gear

    /// Gear whose protection hidden damage or age can undo: makers and safety bodies (CPSC, NHTSA, helmet makers)
    /// say not to buy it second-hand or keep it past its life.
    static let safetyGearTerms = ["helmet", "car seat", "child seat", "booster seat", "infant seat", "baby seat",
                                  "crib", "harness", "life jacket", "life vest", "smoke alarm", "smoke detector",
                                  "carbon monoxide"]

    /// A second-hand, refurbished or kept-longer swap for safety gear ("Second-hand bike helmet", "Keep your helmet
    /// longer"), which is never suggested. The swap's whole name counts (a used bike "with child seat" includes a used
    /// seat); of the original only what comes before "with", so a used bike for a "bicycle with child seat" is fine.
    public func isUnsafeSecondHand(replacing original: Component) -> Bool {
        let swapName = name.lowercased()
        let originalHead = original.name.lowercased().components(separatedBy: " with ").first ?? ""
        let isGear = Self.safetyGearTerms.contains { swapName.contains($0) }
            || (category == original.category && Self.safetyGearTerms.contains { originalHead.contains($0) })
        guard isGear else { return false }
        let keptLonger = lifespanYears != nil || swapName.contains("keep") || swapName.contains("longer")
        return condition != .new || Condition(name: name) != .new || keptLonger
    }
}

/// Cost and effort of adopting an alternative.
public struct Practicality: Codable, Sendable, Hashable {
    public enum CostTier: String, Codable, Sendable, Hashable, CaseIterable { case lower, similar, higher }
    public enum Effort: String, Codable, Sendable, Hashable, CaseIterable { case easy, moderate, hard }

    public var cost: CostTier
    public var effort: Effort

    public init(cost: CostTier = .similar, effort: Effort = .easy) {
        self.cost = cost
        self.effort = effort
    }
}
