import Foundation

/// The meal a food scan was most likely of, by the hour it was taken.
public enum MealTime: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    public init(hour: Int) {
        switch hour {
        case 5..<11: self = .breakfast
        case 11..<16: self = .lunch
        case 16..<22: self = .dinner
        default: self = .snack
        }
    }

    /// The meal a scan's title names ("Lunch", "Sunday brunch"), if any.
    public init?(title: String) {
        let words = Set(title.lowercased().split { !$0.isLetter }.map(String.init))
        if !words.isDisjoint(with: ["breakfast", "brunch"]) { self = .breakfast }
        else if words.contains("lunch") { self = .lunch }
        else if !words.isDisjoint(with: ["dinner", "supper"]) { self = .dinner }
        else { return nil }
    }

    public var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    public var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }

    public var plural: String { self == .lunch ? "lunches" : rawValue + "s" }

    /// When the meal usually starts, minutes after midnight, for a meal with no scans to learn from.
    public var usualStartMinute: Int {
        switch self {
        case .breakfast: 8 * 60
        case .lunch: 12 * 60
        case .dinner: 18 * 60 + 30
        case .snack: 15 * 60
        }
    }
}

/// A pattern in the user's food scans worth acting on: a meal that keeps coming out high in carbon.
public struct MealTrend: Sendable, Hashable, Identifiable {
    public var mealTime: MealTime
    /// The meal's scans, newest first.
    public var scanIDs: [UUID]
    /// Average carbon per meal, kg CO2e.
    public var averageCarbonKg: Double
    public var latestCarbonKg: Double
    /// The biggest item in the latest scan, which the nudge is about.
    public var latestScanID: UUID
    public var topComponentID: UUID
    public var topItemName: String
    /// Share of the latest meal's carbon that item is, 0–1.
    public var topItemShare: Double
    /// When the meal is usually eaten, minutes after midnight, from the scan times.
    public var typicalMinute: Int

    public var id: MealTime { mealTime }

    /// Why it was flagged, in one sentence.
    public var reason: String {
        let share = Int((topItemShare * 100).rounded())
        let latest = String(format: "%.1f", latestCarbonKg)
        if scanIDs.count > 1 {
            let average = String(format: "%.1f", averageCarbonKg)
            return "Your last \(scanIDs.count) \(mealTime.plural) averaged \(average) kg CO₂e; the \(topItemName.lowercased()) was \(share)% of the latest one."
        }
        return "This \(mealTime.rawValue) came to \(latest) kg CO₂e, and the \(topItemName.lowercased()) was \(share)% of it."
    }

    /// Minutes before the meal that a nudge goes out, so it arrives while the user is still deciding.
    public static let leadMinutes = 20

    /// The next time a nudge for this meal would go out: `leadMinutes` before the typical start, on the next day that
    /// time is still ahead.
    public func nextSendDate(after now: Date, calendar: Calendar = .current) -> Date {
        let minute = max(0, typicalMinute - Self.leadMinutes)
        let today = calendar.startOfDay(for: now)
        let candidate = calendar.date(byAdding: .minute, value: minute, to: today) ?? now
        return candidate > now ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }
}

public enum MealTrends {
    /// Per-meal carbon above which a meal is worth a nudge, kg CO2e. A plant-based plate is usually under 1 kg; a beef
    /// burger meal is 3–5.
    public static let highCarbonKg = 1.5

    /// Meals that came out high in carbon, one trend per meal time, worst first. A scan counts as a meal when most
    /// of what it totals is food (packaging and drinks with it are fine); screenshots don't count.
    public static func analyze(_ scans: [ScanResult], calendar: Calendar = .current) -> [MealTrend] {
        let meals = scans.compactMap { scan -> (scan: ScanResult, carbon: Double, time: MealTime, minute: Int)? in
            guard !scan.isScreenshot, let carbon = mealCarbon(scan) else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: scan.date)
            let hour = parts.hour ?? 12
            let byClock = MealTime(hour: hour)
            // A title that names the meal wins; scanned at another hour, the meal's usual time stands in.
            guard let named = MealTime(title: scan.title), named != byClock else {
                return (scan, carbon, byClock, hour * 60 + (parts.minute ?? 0))
            }
            return (scan, carbon, named, named.usualStartMinute)
        }
        let byTime = Dictionary(grouping: meals, by: \.time)
        let trends = byTime.compactMap { time, group -> MealTrend? in
            let ordered = group.sorted { $0.scan.date > $1.scan.date }
            guard let latest = ordered.first, let top = topFood(latest.scan) else { return nil }
            let recent = Array(ordered.prefix(5))
            let average = recent.map(\.carbon).reduce(0, +) / Double(recent.count)
            guard latest.carbon >= highCarbonKg || average >= highCarbonKg else { return nil }
            let minutes = recent.map(\.minute).sorted()
            return MealTrend(mealTime: time, scanIDs: recent.map(\.scan.id), averageCarbonKg: average,
                             latestCarbonKg: latest.carbon, latestScanID: latest.scan.id, topComponentID: top.component.id,
                             topItemName: top.component.name, topItemShare: latest.carbon > 0 ? top.carbon / latest.carbon : 0,
                             typicalMinute: minutes[minutes.count / 2])
        }
        return trends.sorted { $0.averageCarbonKg > $1.averageCarbonKg }
    }

    /// The meal's carbon, or nil when the scan is not mostly food.
    public static func mealCarbon(_ scan: ScanResult) -> Double? {
        let counted = scan.totaledComponents
        let food = counted.filter { $0.category == .food }
        guard !food.isEmpty, food.count * 2 >= counted.filter({ $0.category != .packaging }).count else { return nil }
        if let total = scan.totals[.carbon]?.value, total > 0 { return total }
        let sum = counted.compactMap { $0.metrics[.carbon]?.value }.reduce(0, +)
        return sum > 0 ? sum : nil
    }

    /// The food item with the most carbon in the scan.
    static func topFood(_ scan: ScanResult) -> (component: Component, carbon: Double)? {
        scan.totaledComponents
            .filter { $0.category == .food }
            .compactMap { component in component.metrics[.carbon].map { (component, $0.value) } }
            .max { $0.1 < $1.1 }
    }
}
