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
            services = ServiceContainer.make(flags: flags, secrets: secrets)
        }
    }
    private(set) var services: ServiceContainer
    let secrets: Secrets
    var selectedTab: AppTab = .scan
    /// Last persistence error, surfaced in Settings.
    private(set) var storageError: String?

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

    func updateProfile(_ profile: UserProfile) {
        self.profile = profile
        perform { try store.saveProfile(profile) }
    }

    func save(_ result: ScanResult) {
        if let index = scans.firstIndex(where: { $0.id == result.id }) {
            scans[index] = result
        } else {
            scans.insert(result, at: 0)
        }
        perform { try store.save(result) }
    }

    func deleteScan(id: UUID) {
        scans.removeAll { $0.id == id }
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
