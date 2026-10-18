import Foundation
import Observation
import GreenCore

/// A text LiveGreen sends at the moment a habit can change: before a meal that has been coming out high in carbon,
/// or on Sunday morning, shopping day, for a single-serve item worth buying in bulk. Each suggests a specific
/// nearby swap.
struct Nudge: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case scheduled, sending, sent, failed }

    enum Occasion: Codable, Hashable {
        case meal(MealTime)
        /// The weekly shop (`ShoppingTrends`: Sunday morning, assumed rather than asked).
        case shopping

        var title: String {
            switch self {
            case .meal(let meal): meal.title
            case .shopping: "Sunday shop"
            }
        }

        var systemImage: String {
            switch self {
            case .meal(let meal): meal.systemImage
            case .shopping: "cart"
            }
        }

        /// How the time it goes out is described: "your usual lunch", "your Sunday shop".
        var moment: String {
            switch self {
            case .meal(let meal): "your usual \(meal.rawValue)"
            case .shopping: "your Sunday shop"
            }
        }

        var key: String {
            switch self {
            case .meal(let meal): meal.rawValue
            case .shopping: "shopping"
            }
        }
    }

    /// The occasion and what it is about (a meal's scan, a shopping item), so a newer scan makes a new nudge.
    var id: String
    var occasion: Occasion
    var scanID: UUID
    /// Why it was flagged (`MealTrend.reason`, `ShoppingTrend.reason`).
    var reason: String
    var message: String
    var swapName: String?
    var placeName: String?
    /// When it would normally go out: shortly before the meal's usual time.
    var scheduledFor: Date
    var status: Status
    var sentAt: Date?
    var error: String?
}

/// Texting the user: their phone number, the Photon line it is assigned to, and the nudges built from their meal
/// trends. Nudges go out by themselves when one is due while the app is open (there is no server to send them while
/// it is closed), and the Nudges tab can send any of them now for a demo.
@Observable
final class NudgeCenter {
    /// E.164, e.g. "+16175550123".
    private(set) var phone: String?
    /// The shared iMessage line Photon assigned to `phone`; the user texts it once to turn nudges on.
    private(set) var lineNumber: String?
    /// Set once the user has texted the line, which is when Photon lets it reply.
    private(set) var conversation: PhotonClient.Conversation?
    private(set) var nudges: [Nudge] = []
    private(set) var trends: [MealTrend] = []
    private(set) var shoppingTrends: [ShoppingTrend] = []
    private(set) var isRefreshing = false
    /// The last problem setting up texting, for the Nudges tab.
    private(set) var setupError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var refreshAgain = false
    static let key = "LiveGreen.nudges"

    private struct Saved: Codable {
        var phone: String?
        var lineNumber: String?
        var conversation: PhotonClient.Conversation?
        var nudges: [Nudge]

        init(phone: String?, lineNumber: String?, conversation: PhotonClient.Conversation?, nudges: [Nudge]) {
            self.phone = phone
            self.lineNumber = lineNumber
            self.conversation = conversation
            self.nudges = nudges
        }

        /// Nudges saved in an older shape are dropped (they are rebuilt from the scans), keeping the phone setup.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            phone = try container.decodeIfPresent(String.self, forKey: .phone)
            lineNumber = try container.decodeIfPresent(String.self, forKey: .lineNumber)
            conversation = try container.decodeIfPresent(PhotonClient.Conversation.self, forKey: .conversation)
            nudges = (try? container.decode([Nudge].self, forKey: .nudges)) ?? []
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            phone = saved.phone
            lineNumber = saved.lineNumber
            conversation = saved.conversation
            nudges = saved.nudges
        }
    }

    var isTextingOn: Bool { conversation != nil }

    var upcoming: [Nudge] {
        nudges.filter { $0.status != .sent }.sorted { $0.scheduledFor < $1.scheduledFor }
    }

    var sent: [Nudge] {
        nudges.filter { $0.status == .sent }.sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }
    }

    func nudge(forScan id: UUID) -> Nudge? { nudges.first { $0.scanID == id && $0.status != .sent } }

    // MARK: - Setup

    /// Saves the number and assigns it a Photon line. Returns the line's number to text.
    @discardableResult
    func register(phone typed: String, name: String?, photon: PhotonClient) async throws -> String {
        guard let handle = PhotonClient.e164(typed) else { throw NudgeError.invalidPhone }
        if handle != phone { conversation = nil }
        phone = handle
        setupError = nil
        save()
        do {
            let line: String
            if let existing = try await photon.existingAssignment(handle: handle) {
                line = existing
            } else {
                line = try await photon.assign(handle: handle, firstName: name)
            }
            lineNumber = line
            save()
            return line
        } catch {
            setupError = Self.describe(error)
            throw error
        }
    }

    /// Checks whether the user has texted their line yet; true once nudges can be sent.
    @discardableResult
    func checkActivation(photon: PhotonClient) async -> Bool {
        guard let phone else { return false }
        do {
            if let found = try await photon.conversation(with: phone) {
                conversation = found
                setupError = nil
                save()
                return true
            }
            setupError = nil
        } catch {
            setupError = Self.describe(error)
        }
        return false
    }

    func forgetPhone() {
        phone = nil
        lineNumber = nil
        conversation = nil
        setupError = nil
        save()
    }

    func removeAll() {
        phone = nil
        lineNumber = nil
        conversation = nil
        nudges = []
        trends = []
        shoppingTrends = []
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - Trends

    /// Re-reads the trends and makes a nudge for each one that has none yet: one per flagged meal, before that meal,
    /// and one for the single-serve item with the most plastic to save, on Sunday morning. Each names the best swap
    /// and the nearby place its action plan chose.
    func refresh(app: AppModel) async {
        guard !isRefreshing else { refreshAgain = true; return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            trends = MealTrends.analyze(app.scans)
            shoppingTrends = ShoppingTrends.analyze(await scansWithSwaps(app: app))
            let shopping = Array(shoppingTrends.prefix(1))
            let wanted = Set(trends.map { Self.id(for: $0) } + shopping.map { Self.id(for: $0) })
            // A scheduled nudge whose scan was deleted or no longer counts goes; sent ones stay as history.
            nudges.removeAll { $0.status != .sent && !wanted.contains($0.id) }
            for trend in trends {
                let id = Self.id(for: trend)
                if reschedule(id, to: trend.nextSendDate(after: Date())) { continue }
                let nudge = await makeNudge(id: id, trend: trend, app: app)
                nudges.append(nudge)
                save()
            }
            for trend in shopping {
                let id = Self.id(for: trend)
                if reschedule(id, to: ShoppingTrends.nextShoppingDate(after: Date())) { continue }
                let nudge = await makeNudge(id: id, trend: trend, app: app)
                nudges.append(nudge)
                save()
            }
            save()
        } while refreshAgain
    }

    static func id(for trend: MealTrend) -> String { "\(trend.mealTime.rawValue)|\(trend.latestScanID.uuidString)" }

    static func id(for trend: ShoppingTrend) -> String { "shopping|\(trend.scanID.uuidString)|\(trend.componentID.uuidString)" }

    /// True when the nudge already exists; a scheduled one whose time passed while the app was closed moves on.
    private func reschedule(_ id: String, to next: Date) -> Bool {
        guard let index = nudges.firstIndex(where: { $0.id == id }) else { return false }
        if nudges[index].status == .scheduled, nudges[index].scheduledFor < Date().addingTimeInterval(-3_600) {
            nudges[index].scheduledFor = next
        }
        return true
    }

    /// Recent scans with single-serve items, with their swaps fetched (the background fetch keeps them off the
    /// stored scan until the swaps screen opens).
    private func scansWithSwaps(app: AppModel) async -> [ScanResult] {
        var result: [ScanResult] = []
        for scan in app.scans.prefix(20) where scan.totaledComponents.contains(where: ShoppingTrends.isSingleServe) {
            result.append(await withSwaps(scan, app: app))
        }
        return result
    }

    private func withSwaps(_ scan: ScanResult, app: AppModel) async -> ScanResult {
        guard !scan.hasAlternatives, let fetched = try? await app.swapPrefetch.swaps(for: scan, app: app) else { return scan }
        return SwapPrefetcher.rebase(fetched, onto: scan, engine: ImpactEngine(reference: app.services.reference),
                                     profile: app.profile)
    }

    private func makeNudge(id: String, trend: MealTrend, app: AppModel) async -> Nudge {
        var swap: Alternative?
        var plan: ActionPlan?
        var component: Component?
        if let saved = app.scans.first(where: { $0.id == trend.latestScanID }) {
            let scan = await withSwaps(saved, app: app)
            component = scan.component(withID: trend.topComponentID)
            if let component {
                let options = AlternativesModel.alternatives(for: component, plugFeatures: false)
                swap = scan.selectedAlternatives[component.id].flatMap { id in options.first { $0.id == id } }
                    ?? SwapMath.defaultPick(for: component, among: options)
                if let swap { plan = await app.actionPlans.ensurePlan(for: swap, replacing: component, app: app) }
            }
        }
        let message = Self.message(trend: trend, component: component, swap: swap, plan: plan, name: app.displayName)
        return Nudge(id: id, occasion: .meal(trend.mealTime), scanID: trend.latestScanID, reason: trend.reason,
                     message: message, swapName: swap?.name, placeName: plan?.place?.name,
                     scheduledFor: trend.nextSendDate(after: Date()), status: .scheduled)
    }

    private func makeNudge(id: String, trend: ShoppingTrend, app: AppModel) async -> Nudge {
        var plan: ActionPlan?
        if let saved = app.scans.first(where: { $0.id == trend.scanID }),
           let component = await withSwaps(saved, app: app).component(withID: trend.componentID) {
            plan = await app.actionPlans.ensurePlan(for: trend.swap, replacing: component, app: app)
        }
        let message = Self.message(trend: trend, plan: plan, name: app.displayName)
        return Nudge(id: id, occasion: .shopping, scanID: trend.scanID, reason: trend.reason, message: message,
                     swapName: trend.swap.name, placeName: plan?.place?.name,
                     scheduledFor: ShoppingTrends.nextShoppingDate(after: Date()), status: .scheduled)
    }

    private static func greeting(_ name: String) -> String {
        name.split(separator: " ").first.map { "Hey \($0)!" } ?? "Hey!"
    }

    /// " at Target (0.6 mi, 1 Porter Square)", or "" without a place.
    private static func placeText(_ plan: ActionPlan?) -> String {
        guard let place = plan?.place else { return "" }
        let distance = place.distanceText(metric: DisplayUnits.system == .metric)
        let street = place.address?.split(separator: ",").first.map(String.init)
        let detail = [distance, street].compactMap { $0 }.joined(separator: ", ")
        return " at \(place.name)" + (detail.isEmpty ? "" : " (\(detail))")
    }

    /// The text: the meal, why it was flagged, and the swap at a named nearby place.
    static func message(trend: MealTrend, component: Component?, swap: Alternative?, plan: ActionPlan?, name: String) -> String {
        var lines = ["\(greeting(name)) \(trend.mealTime.title) is coming up 🌱", trend.reason]
        if let swap {
            var suggestion = "Today, try a \(swap.name.lowercased())" + placeText(plan)
            if let before = component?.metrics[.carbon]?.value, let after = swap.metrics[.carbon]?.value, before > 0, after < before {
                suggestion += ". That's about \(Int(((before - after) / before * 100).rounded()))% less carbon"
            }
            lines.append(suggestion + ".")
        } else {
            lines.append("Today, try a plant-based option instead of the \(trend.topItemName.lowercased()).")
        }
        lines.append("Your step-by-step plan is in LiveGreen.")
        return lines.joined(separator: "\n")
    }

    /// The Sunday text: shopping day, the single-serve item, and the bulk swap at a named nearby store.
    static func message(trend: ShoppingTrend, plan: ActionPlan?, name: String) -> String {
        let cut = Int((trend.plasticCut * 100).rounded())
        return [
            "\(greeting(name)) It's Sunday, shopping day 🛒",
            trend.reason,
            "This week, pick up \(trend.swap.name.lowercased())\(placeText(plan)) instead. That's about \(cut)% less plastic.",
            "Your step-by-step plan is in LiveGreen.",
        ].joined(separator: "\n")
    }

    // MARK: - Sending

    /// Sends a nudge now, whatever its scheduled time. Sending one again (a demo) sends a new message.
    func send(_ nudge: Nudge, photon: PhotonClient) async {
        guard let index = nudges.firstIndex(where: { $0.id == nudge.id }) else { return }
        nudges[index].status = .sending
        nudges[index].error = nil
        do {
            if conversation == nil { await checkActivation(photon: photon) }
            guard phone != nil else { throw NudgeError.noPhone }
            guard let conversation else {
                throw NudgeError.notActivated(line: lineNumber)
            }
            let key = "livegreen-nudge-\(nudge.id)-\(Int(Date().timeIntervalSince1970))"
            try await photon.sendText(nudge.message, in: conversation, idempotencyKey: key)
            nudges[index].status = .sent
            nudges[index].sentAt = Date()
        } catch {
            nudges[index].status = .failed
            nudges[index].error = Self.describe(error)
        }
        save()
    }

    /// Sends every scheduled nudge whose time has come. Called while the app is open.
    func sendDue(photon: PhotonClient, now: Date = Date()) async {
        guard isTextingOn || lineNumber != nil else { return }
        for nudge in nudges where nudge.status == .scheduled && nudge.scheduledFor <= now {
            await send(nudge, photon: photon)
        }
    }

    private func save() {
        let saved = Saved(phone: phone, lineNumber: lineNumber, conversation: conversation, nudges: nudges)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key) }
    }

    static func describe(_ error: any Error) -> String {
        if let nudge = error as? NudgeError { return nudge.message }
        switch error as? GreenCoreError {
        case .missingAPIKey(let key): return "Add a \(key) in Settings → API keys to send texts."
        case .http(let status, let body): return "Photon returned \(status): \(body)"
        case .timeout: return "Photon took too long to answer."
        default: return error.localizedDescription
        }
    }
}

enum NudgeError: Error {
    case invalidPhone
    case noPhone
    case notActivated(line: String?)

    var message: String {
        switch self {
        case .invalidPhone: "That doesn't look like a phone number. Include the area code."
        case .noPhone: "Add your phone number above to get texts."
        case .notActivated(let line):
            "Text anything to \(line.map(PhoneFormat.pretty) ?? "your LiveGreen number") first. iMessage only lets the line reply once you've messaged it."
        }
    }
}

nonisolated enum PhoneFormat {
    /// "+16175550123" → "(617) 555-0123"; other countries as given.
    static func pretty(_ e164: String) -> String {
        let digits = e164.filter(\.isNumber)
        guard e164.hasPrefix("+1"), digits.count == 11 else { return e164 }
        let d = Array(digits.dropFirst())
        return "(\(String(d[0..<3]))) \(String(d[3..<6]))-\(String(d[6..<10]))"
    }
}
