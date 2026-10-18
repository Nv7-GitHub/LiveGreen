import Foundation

/// A single-serve packaged item the user keeps buying, with a bulk swap that cuts its packaging: a Premier Protein
/// bottle a day becomes one tub of protein powder.
public struct ShoppingTrend: Sendable, Hashable, Identifiable {
    /// The newest scan the item is in, and the item there.
    public var scanID: UUID
    public var componentID: UUID
    public var itemName: String
    public var swap: Alternative
    /// Scans the item shows up in.
    public var scanCount: Int
    /// Share of the item's yearly plastic the swap avoids, 0–1.
    public var plasticCut: Double
    /// Plastic avoided a year, g.
    public var yearlyPlasticSavedG: Double

    public var id: String { itemName.lowercased() }

    /// Why it was flagged, in one sentence.
    public var reason: String {
        let seen = scanCount > 1 ? "You've scanned \(itemName) \(scanCount) times" : "You scanned \(itemName)"
        let grams = yearlyPlasticSavedG >= 1_000 ? String(format: "%.1f kg", yearlyPlasticSavedG / 1_000)
                                                 : "\(Int(yearlyPlasticSavedG.rounded())) g"
        let change = isBulk ? "buying in bulk" : "switching to \(swap.name.lowercased())"
        return "\(seen), each one packed on its own; \(change) skips about \(grams) of plastic a year."
    }

    /// Whether the swap is the same thing in a bigger pack, which the text calls buying in bulk.
    public var isBulk: Bool {
        let name = swap.name.lowercased()
        return ["bulk", "tub", "refill", "family size", "large pack", "multipack", "big bag", "jug"].contains { name.contains($0) }
    }
}

public enum ShoppingTrends {
    /// The user's shopping day and time. Not asked for: Sunday morning is assumed.
    public static let weekday = 1
    public static let hour = 10

    /// The share of an item's plastic a swap has to avoid to be worth a shopping nudge.
    public static let minimumPlasticCut = 0.4

    /// The next shopping time: Sunday at 10 am, today if it is Sunday before then.
    public static func nextShoppingDate(after now: Date, calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
    }

    /// Items with a bulk swap, most plastic saved first, one per kind of item (the newest scan's copy).
    public static func analyze(_ scans: [ScanResult]) -> [ShoppingTrend] {
        var counts: [String: Int] = [:]
        for scan in scans {
            for name in Set(scan.totaledComponents.filter(isSingleServe).map { $0.name.lowercased() }) {
                counts[name, default: 0] += 1
            }
        }
        var trends: [String: ShoppingTrend] = [:]
        for scan in scans.sorted(by: { $0.date > $1.date }) where !scan.isScreenshot {
            for component in scan.totaledComponents where isSingleServe(component) {
                let key = component.name.lowercased()
                guard trends[key] == nil, let best = bulkSwap(for: component) else { continue }
                trends[key] = ShoppingTrend(scanID: scan.id, componentID: component.id, itemName: component.name,
                                            swap: best.swap, scanCount: counts[key] ?? 1, plasticCut: best.cut,
                                            yearlyPlasticSavedG: best.savedG)
            }
        }
        return trends.values.sorted { $0.yearlyPlasticSavedG > $1.yearlyPlasticSavedG }
    }

    /// Something bought again and again in its own plastic: a consumable (not a durable item) with plastic in it.
    public static func isSingleServe(_ component: Component) -> Bool {
        [.food, .packaging, .personalCare].contains(component.category) && !SwapMath.isDurable(component)
            && (component.metrics[.plasticMass]?.value ?? 0) > 0
    }

    /// The accepted swap that avoids the most plastic a year, when it avoids at least `minimumPlasticCut` of it and
    /// adds no carbon.
    public static func bulkSwap(for component: Component) -> (swap: Alternative, cut: Double, savedG: Double)? {
        guard let plastic = component.metrics[.plasticMass]?.value, plastic > 0 else { return nil }
        let baseline = plastic * SwapMath.yearlyFactor(.plasticMass, for: component)
        guard baseline > 0 else { return nil }
        return component.alternatives
            .filter { $0.kind == .product && GreenScore.accepts($0, replacing: component, engine: SwapMath.engine)
                && !SwapMath.raisesCarbon(component, $0) }
            .compactMap { swap -> (swap: Alternative, cut: Double, savedG: Double)? in
                guard let saved = SwapMath.yearlySaving(.plasticMass, component: component, alternative: swap)?.value,
                      saved / baseline >= minimumPlasticCut else { return nil }
                return (swap, min(saved / baseline, 1), saved)
            }
            .max { $0.savedG < $1.savedG }
    }
}
