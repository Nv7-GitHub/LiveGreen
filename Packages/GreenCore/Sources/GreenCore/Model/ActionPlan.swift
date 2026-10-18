import Foundation

/// A real place near the user where a swap can be bought or done, found by an on-device map search.
public struct NearbyPlace: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var address: String?
    public var latitude: Double
    public var longitude: Double
    /// Straight-line distance from the user, metres.
    public var distanceMeters: Double?
    public var phone: String?
    public var url: URL?
    /// The map's point-of-interest category, e.g. "Restaurant", "Grocery store".
    public var categoryName: String?

    public var id: String { "\(name)|\(String(format: "%.5f,%.5f", latitude, longitude))" }

    public init(name: String, address: String? = nil, latitude: Double, longitude: Double, distanceMeters: Double? = nil,
                phone: String? = nil, url: URL? = nil, categoryName: String? = nil) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
        self.phone = phone
        self.url = url
        self.categoryName = categoryName
    }

    /// "0.3 mi" / "450 m" style, for prompts and texts.
    public func distanceText(metric: Bool) -> String? {
        guard let distanceMeters else { return nil }
        if metric {
            return distanceMeters < 1_000 ? "\(Int((distanceMeters / 10).rounded() * 10)) m"
                                          : String(format: "%.1f km", distanceMeters / 1_000)
        }
        let miles = distanceMeters / 1_609.344
        return miles < 0.1 ? "\(Int((distanceMeters * 3.28084 / 10).rounded() * 10)) ft" : String(format: "%.1f mi", miles)
    }
}

/// One thing to do, in order.
public struct ActionStep: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var title: String
    public var detail: String?

    public init(id: UUID = UUID(), title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// What to do to take one swap: where to go and the steps, written for this user and this place.
public struct ActionPlan: Codable, Sendable, Hashable {
    public var alternativeID: UUID
    /// One line, e.g. "Get a lentil burger at Clover Food Lab, 0.3 mi away".
    public var headline: String
    /// The place the steps are written for; nil for a swap that needs no trip (line-drying, keeping a laptop).
    public var place: NearbyPlace?
    /// Other nearby options, closest first.
    public var otherPlaces: [NearbyPlace]
    public var steps: [ActionStep]
    public var createdAt: Date

    public init(alternativeID: UUID, headline: String, place: NearbyPlace?, otherPlaces: [NearbyPlace] = [],
                steps: [ActionStep], createdAt: Date = Date()) {
        self.alternativeID = alternativeID
        self.headline = headline
        self.place = place
        self.otherPlaces = otherPlaces
        self.steps = steps
        self.createdAt = createdAt
    }
}

/// What a planner writes: the headline, which of the given places it chose, and the steps.
public struct ActionPlanDraft: Sendable, Hashable {
    public var headline: String
    /// Index into the request's places, or nil when none fits or none is needed.
    public var placeIndex: Int?
    public var steps: [ActionStep]

    public init(headline: String, placeIndex: Int?, steps: [ActionStep]) {
        self.headline = headline
        self.placeIndex = placeIndex
        self.steps = steps
    }
}

/// Everything a planner is told about one swap.
public struct ActionPlanRequest: Sendable {
    public var original: Component
    public var alternative: Alternative
    public var places: [NearbyPlace]
    public var profile: UserProfile
    /// "Cambridge, MA", when known.
    public var locality: String?
    public var metricUnits: Bool

    public init(original: Component, alternative: Alternative, places: [NearbyPlace], profile: UserProfile,
                locality: String? = nil, metricUnits: Bool = false) {
        self.original = original
        self.alternative = alternative
        self.places = places
        self.profile = profile
        self.locality = locality
        self.metricUnits = metricUnits
    }
}

/// Turns a swap and the places near the user into concrete steps.
public protocol ActionPlanner: Sendable {
    func planActions(_ request: ActionPlanRequest) async throws -> ActionPlanDraft
}

public enum ActionPlanning {
    /// Map searches to try for a swap, best first. Empty when the swap is a change of habit that needs no trip.
    public static func placeQueries(for alternative: Alternative, replacing original: Component) -> [String] {
        if alternative.kind == .smartPlugScheduling { return ["smart plug", "electronics store"] }
        let name = alternative.name.lowercased()
        if name.hasPrefix("repair") || name.hasPrefix("fix ") {
            switch original.category {
            case .clothing: return ["tailor", "shoe repair"]
            case .vehicle: return ["bike repair", "auto repair"]
            default: return ["electronics repair", "repair shop"]
            }
        }
        if !alternative.isPurchase, Alternative.behaviourPrefixes.contains(where: { name.hasPrefix($0) }) { return [] }
        let item = cleanedItemName(alternative.name)
        switch alternative.condition {
        case .used, .refurbished:
            switch alternative.category {
            case .electronic: return ["refurbished \(item)", "used electronics store", "electronics store"]
            case .clothing: return ["thrift store", "consignment store"]
            case .vehicle: return ["used \(item)", "used car dealer"]
            default: return ["thrift store", "secondhand store"]
            }
        case .new:
            break
        }
        let fallback: [String] = switch Alternative.scoredCategory(alternative.category, isReusable: alternative.isReusable) {
        case .food: original.category == .food ? ["vegetarian restaurant", "grocery store"] : ["grocery store"]
        case .electronic: ["electronics store"]
        case .clothing: ["clothing store", "thrift store"]
        case .packaging: ["grocery store"]
        case .household: ["home goods store", "kitchen supply store"]
        case .personalCare: ["pharmacy", "grocery store"]
        case .vehicle: ["bike shop", "car dealer"]
        }
        return [item] + fallback
    }

    /// The swap's name without buying words: "Buy a used bicycle" → "bicycle".
    static func cleanedItemName(_ name: String) -> String {
        var words = name.split(separator: " ").map(String.init)
        let dropped: Set<String> = ["buy", "a", "an", "used", "refurbished", "second-hand", "secondhand", "new", "switch", "to"]
        while let first = words.first, dropped.contains(first.lowercased()) { words.removeFirst() }
        return words.joined(separator: " ").lowercased()
    }
}

/// Template steps from the swap and the closest place, with no network. Used in demo mode and whenever the AI
/// planner fails, so a plan always shows.
public struct LocalActionPlanner: ActionPlanner {
    public init() {}

    public func planActions(_ request: ActionPlanRequest) async throws -> ActionPlanDraft {
        Self.draft(for: request)
    }

    public static func draft(for request: ActionPlanRequest) -> ActionPlanDraft {
        let swap = request.alternative
        let item = swap.kind == .smartPlugScheduling ? "a smart plug" : swap.name
        guard let place = request.places.first else {
            return ActionPlanDraft(headline: swap.name, placeIndex: nil, steps: [
                ActionStep(title: "Start with \(swap.name.lowercased())", detail: swap.rationale),
                ActionStep(title: "Do it again next time", detail: "Small swaps add up when they become the habit."),
            ])
        }
        let distance = place.distanceText(metric: request.metricUnits).map { ", \($0) away" } ?? ""
        let isFood = swap.category == .food
        var steps = [
            ActionStep(title: "Head to \(place.name)", detail: [place.address, distance.isEmpty ? nil : String(distance.dropFirst(2))]
                .compactMap { $0 }.joined(separator: " · ")),
            ActionStep(title: isFood ? "Order the \(swap.name.lowercased())" : "Ask for \(item.lowercased())",
                       detail: swap.rationale),
        ]
        if swap.isReusable {
            steps.append(ActionStep(title: "Keep it where you'll use it", detail: "Leave it by the door or in your bag so it replaces the throwaway one."))
        } else if !isFood, request.original.category != .food {
            steps.append(ActionStep(title: "Recycle or donate the old one", detail: "Drop it off rather than binning it."))
        } else {
            steps.append(ActionStep(title: "Make it your usual", detail: "Pick it again next time and the savings below repeat every week."))
        }
        let lowered = item.lowercased()
        let article = lowered.hasPrefix("a ") || lowered.hasSuffix("s") ? "" : "aeiou".contains(lowered.prefix(1)) ? "an " : "a "
        return ActionPlanDraft(headline: "\(isFood ? "Get" : "Pick up") \(article)\(lowered) at \(place.name)\(distance)",
                               placeIndex: 0, steps: steps)
    }
}
