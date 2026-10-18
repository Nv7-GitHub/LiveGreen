import Foundation
import Observation
import CoreLocation
import GreenCore

/// Action plans for picked swaps: the nearby place to get each one and the steps, plus which steps the user has
/// ticked off. Plans are kept per swap (alternative id) in UserDefaults, so reopening a scan shows the same plan
/// and the nudges can name the same place.
@Observable
final class ActionPlans {
    private(set) var plans: [UUID: ActionPlan] = [:]
    private(set) var completedSteps: Set<UUID> = []
    /// Swaps currently being planned.
    private(set) var planning: Set<UUID> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tasks: [UUID: Task<ActionPlan, Never>] = [:]
    static let plansKey = "LiveGreen.actionPlans"
    static let stepsKey = "LiveGreen.actionPlanSteps"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.plansKey),
           let saved = try? JSONDecoder().decode([UUID: ActionPlan].self, from: data) { plans = saved }
        if let data = defaults.data(forKey: Self.stepsKey),
           let saved = try? JSONDecoder().decode(Set<UUID>.self, from: data) { completedSteps = saved }
    }

    func plan(for alternative: Alternative) -> ActionPlan? { plans[alternative.id] }

    func isDone(_ step: ActionStep) -> Bool { completedSteps.contains(step.id) }

    func toggle(_ step: ActionStep) {
        if completedSteps.contains(step.id) { completedSteps.remove(step.id) } else { completedSteps.insert(step.id) }
        save()
    }

    /// Done steps out of all steps for a swap's plan.
    func progress(for alternative: Alternative) -> (done: Int, total: Int)? {
        guard let plan = plans[alternative.id] else { return nil }
        return (plan.steps.filter { completedSteps.contains($0.id) }.count, plan.steps.count)
    }

    /// The saved plan, or a new one: find places near the user for the swap, then have the planner write the steps.
    /// A planner failure falls back to template steps, so a plan always comes back.
    @discardableResult
    func ensurePlan(for alternative: Alternative, replacing component: Component, app: AppModel,
                    fresh: Bool = false) async -> ActionPlan {
        if !fresh, let plan = plans[alternative.id] { return plan }
        if let running = tasks[alternative.id] { return await running.value }
        planning.insert(alternative.id)
        let services = app.services
        let profile = app.profile
        let metric = DisplayUnits.system == .metric
        let task = Task { @MainActor in
            let queries = ActionPlanning.placeQueries(for: alternative, replacing: component)
            var places: [NearbyPlace] = []
            var locality: String?
            if !queries.isEmpty {
                let location = await LocationProvider.shared.location(region: profile.region)
                places = await NearbyPlaceSearch.search(queries, near: location)
                locality = LocationProvider.shared.locality
            }
            let request = ActionPlanRequest(original: component, alternative: alternative, places: places,
                                            profile: profile, locality: locality, metricUnits: metric)
            let draft: ActionPlanDraft
            do {
                draft = try await AlternativesModel.withTimeout(.seconds(45)) {
                    try await services.planner.planActions(request)
                }
            } catch {
                draft = LocalActionPlanner.draft(for: request)
            }
            let place = draft.placeIndex.map { places[$0] }
            return ActionPlan(alternativeID: alternative.id, headline: draft.headline, place: place,
                              otherPlaces: places.filter { $0 != place }.prefix(3).map { $0 }, steps: draft.steps)
        }
        tasks[alternative.id] = task
        let plan = await task.value
        tasks[alternative.id] = nil
        planning.remove(alternative.id)
        plans[alternative.id] = plan
        save()
        return plan
    }

    /// Switches a plan to another nearby place, rewriting its steps for it.
    func choose(_ place: NearbyPlace, for alternative: Alternative, replacing component: Component, app: AppModel) async {
        guard let current = plans[alternative.id] else { return }
        let places = [place] + ([current.place].compactMap { $0 } + current.otherPlaces).filter { $0 != place }
        planning.insert(alternative.id)
        let request = ActionPlanRequest(original: component, alternative: alternative, places: [place],
                                        profile: app.profile, locality: LocationProvider.shared.locality,
                                        metricUnits: DisplayUnits.system == .metric)
        let planner = app.services.planner
        let draft = (try? await AlternativesModel.withTimeout(.seconds(45)) { try await planner.planActions(request) })
            ?? LocalActionPlanner.draft(for: request)
        plans[alternative.id] = ActionPlan(alternativeID: alternative.id, headline: draft.headline, place: place,
                                           otherPlaces: Array(places.dropFirst().prefix(3)), steps: draft.steps)
        planning.remove(alternative.id)
        save()
    }

    func removeAll() {
        plans = [:]
        completedSteps = []
        defaults.removeObject(forKey: Self.plansKey)
        defaults.removeObject(forKey: Self.stepsKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(plans) { defaults.set(data, forKey: Self.plansKey) }
        if let data = try? JSONEncoder().encode(completedSteps) { defaults.set(data, forKey: Self.stepsKey) }
    }
}
