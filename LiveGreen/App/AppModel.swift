import Foundation
import Observation
import SwiftData
import GreenCore
import GreenCoreFakes

/// App-wide state: profile, saved scans, feature flags and the service container.
@Observable
final class AppModel {
    var profile: UserProfile
    private(set) var scans: [ScanResult] = []
    var flags: FeatureFlags {
        didSet {
            guard flags != oldValue else { return }
            flags.save()
            // Scan mode and plug visibility don't change the services, so background swap fetches keep running.
            guard flags.servicesDiffer(from: oldValue) else { return }
            services = ServiceContainer.make(flags: flags, secrets: secrets)
            swapPrefetch.reset()
        }
    }
    private(set) var services: ServiceContainer
    let secrets: Secrets
    var selectedTab: AppTab = .scan
    /// Last persistence error, surfaced in Settings.
    private(set) var storageError: String?
    /// Greener swaps fetched in the background for scans whose swaps screen has not been opened yet.
    @ObservationIgnored let swapPrefetch = SwapPrefetcher()
    /// Scans deleted this session. A results or swaps screen still showing one (say, on the Scan tab) must not
    /// save it back or start fetching its swaps; every new scan gets a fresh id, so nothing else is affected.
    @ObservationIgnored private var deletedScanIDs: Set<UUID> = []

    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored private var store: ScanStore { ScanStore(context: container.mainContext) }

    init(container: ModelContainer, launch: LaunchArguments = LaunchArguments(), secrets: Secrets = Secrets()) {
        let flags = FeatureFlags.load(arguments: launch)
        self.container = container
        self.secrets = secrets
        self.flags = flags
        self.services = ServiceContainer.make(flags: flags, secrets: secrets)
        let store = ScanStore(context: container.mainContext)
        var profile = (try? store.profile()) ?? .default
        if launch.skipOnboarding { profile.onboardingCompleted = true }
        self.profile = profile
        self.scans = (try? store.allScans()) ?? []
    }

    /// In-memory model for SwiftUI previews.
    static func preview() -> AppModel {
        let model = AppModel(container: try! Persistence.makeContainer(inMemory: true),
                             launch: LaunchArguments(["-DemoMode", "YES", "-SkipOnboarding", "YES"]))
        return model
    }

    var needsOnboarding: Bool { !profile.onboardingCompleted }

    func completeOnboarding(with profile: UserProfile) {
        var completed = profile
        completed.onboardingCompleted = true
        updateProfile(completed)
    }

    /// Clears the onboarding answers so RootView shows onboarding again. Scan history is kept.
    func resetOnboarding() {
        updateProfile(.default)
    }

    func updateProfile(_ profile: UserProfile) {
        self.profile = profile
        perform { try store.saveProfile(profile) }
    }

    func save(_ result: ScanResult) {
        guard !deletedScanIDs.contains(result.id) else { return }
        if let index = scans.firstIndex(where: { $0.id == result.id }) {
            scans[index] = result
        } else {
            scans.insert(result, at: 0)
        }
        perform { try store.save(result) }
        prefetchSwaps(for: result)
    }

    /// Starts fetching a scan's greener swaps in the background, with no UI, unless the saved copy has them or a
    /// fetch for the same items is running, so "See greener swaps" opens on finished results.
    func prefetchSwaps(for result: ScanResult) {
        guard !deletedScanIDs.contains(result.id) else { return }
        swapPrefetch.prefetch(scans.first { $0.id == result.id } ?? result, app: self)
    }

    /// Removes a scan from History and the Leaderboard (both read `scans`), stops its background swap fetches and
    /// deletes the stored row with its photo and greener image. Cached metric lookups stay: they are keyed by
    /// product (GTIN or brand and model), shared by every scan of it, and hold nothing about this scan.
    func deleteScan(id: UUID) {
        deletedScanIDs.insert(id)
        scans.removeAll { $0.id == id }
        swapPrefetch.forget(id)
        perform { try store.deleteScan(id: id) }
    }

    /// A coordinator bound to the current services and profile.
    func makeScanCoordinator(mode: ScanMode? = nil, scene: DemoScene? = nil) -> ScanCoordinator {
        let services = scene.map { self.services.replaying($0) } ?? self.services
        return ScanCoordinator(services: services, profile: profile, mode: mode ?? flags.scanMode,
                               cache: services.isDemo ? nil : ScanCache(container: container))
    }

    func refreshServices() {
        services = ServiceContainer.make(flags: flags, secrets: secrets)
        swapPrefetch.reset()
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }
}
