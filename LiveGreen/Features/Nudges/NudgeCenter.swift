import Foundation
import Observation
import GreenCore

/// A text LiveGreen sends before a meal that has been coming out high in carbon, suggesting a specific nearby swap.
struct Nudge: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case scheduled, sending, sent, failed }

    /// The meal and the scan it is about, so a newer scan of the same meal makes a new nudge.
    var id: String
    var mealTime: MealTime
    var scanID: UUID
    /// Why the meal was flagged (`MealTrend.reason`).
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
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - Trends

    /// Re-reads the meal trends and makes a nudge for each flagged meal that has none for its latest scan. Each
    /// names the meal's biggest item's best swap and the nearby place its action plan chose.
    func refresh(app: AppModel) async {
        guard !isRefreshing else { refreshAgain = true; return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            trends = MealTrends.analyze(app.scans)
            let flagged = Set(trends.map(\.latestScanID))
            // A scheduled nudge whose scan was deleted or no longer counts goes; sent ones stay as history.
            nudges.removeAll { $0.status != .sent && !flagged.contains($0.scanID) }
            for trend in trends {
                let id = "\(trend.mealTime.rawValue)|\(trend.latestScanID.uuidString)"
                if let index = nudges.firstIndex(where: { $0.id == id }) {
                    if nudges[index].status == .scheduled, nudges[index].scheduledFor < Date().addingTimeInterval(-3_600) {
                        nudges[index].scheduledFor = trend.nextSendDate(after: Date())
                    }
                    continue
                }
                // An older scan's nudge for the same meal is replaced by this one.
                nudges.removeAll { $0.mealTime == trend.mealTime && $0.status != .sent }
                let nudge = await makeNudge(id: id, trend: trend, app: app)
                nudges.append(nudge)
                save()
            }
            save()
        } while refreshAgain
    }

    private func makeNudge(id: String, trend: MealTrend, app: AppModel) async -> Nudge {
        var swap: Alternative?
        var plan: ActionPlan?
        var component: Component?
        if var scan = app.scans.first(where: { $0.id == trend.latestScanID }) {
            if !scan.hasAlternatives, let fetched = try? await app.swapPrefetch.swaps(for: scan, app: app) {
                scan = SwapPrefetcher.rebase(fetched, onto: scan, engine: ImpactEngine(reference: app.services.reference),
                                             profile: app.profile)
            }
            component = scan.component(withID: trend.topComponentID)
            if let component {
                let options = AlternativesModel.alternatives(for: component, plugFeatures: false)
                swap = scan.selectedAlternatives[component.id].flatMap { id in options.first { $0.id == id } }
                    ?? SwapMath.defaultPick(for: component, among: options)
                if let swap { plan = await app.actionPlans.ensurePlan(for: swap, replacing: component, app: app) }
            }
        }
        let message = Self.message(trend: trend, component: component, swap: swap, plan: plan, name: app.displayName)
        return Nudge(id: id, mealTime: trend.mealTime, scanID: trend.latestScanID, reason: trend.reason, message: message,
                     swapName: swap?.name, placeName: plan?.place?.name, scheduledFor: trend.nextSendDate(after: Date()),
                     status: .scheduled)
    }

    /// The text: the meal, why it was flagged, and the swap at a named nearby place.
    static func message(trend: MealTrend, component: Component?, swap: Alternative?, plan: ActionPlan?, name: String) -> String {
        let first = name.split(separator: " ").first.map(String.init)
        let greeting = first.map { "Hey \($0)!" } ?? "Hey!"
        var lines = ["\(greeting) \(trend.mealTime.title) is coming up 🌱", trend.reason]
        if let swap {
            var suggestion = "Today, try a \(swap.name.lowercased())"
            if let place = plan?.place {
                let distance = place.distanceText(metric: DisplayUnits.system == .metric)
                let street = place.address?.split(separator: ",").first.map(String.init)
                let detail = [distance, street].compactMap { $0 }.joined(separator: ", ")
                suggestion += " at \(place.name)" + (detail.isEmpty ? "" : " (\(detail))")
            }
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
