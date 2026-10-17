import Foundation
import GreenCore
import GreenCoreFakes

/// Every external dependency behind its GreenCore protocol. Built from feature flags and secrets.
nonisolated struct ServiceContainer: Sendable {
    var vision: any VisionIdentifier
    var alternatives: any AlternativeSuggester
    var researcher: any SpecResearcher
    var imageEditor: any ImageEditor
    var products: any ProductDatabase
    var appliances: any ApplianceDatabase
    var grid: any GridSignal
    var reference: any ReferenceProviding
    /// The paired (or mock) plug; nil when none is paired.
    var plug: (any PlugController)?
    /// Evidence-ladder resolvers, any order (the ladder sorts by tier).
    var resolvers: [any MetricResolver]
    var modelChoice: ClaudeModel
    var isDemo: Bool

    /// Offline services backed by GreenCoreFakes fixtures (spec §11 demo mode).
    static func demo(scene: DemoScene = .deskSetup, latency: Duration = .milliseconds(450),
                     modelChoice: ClaudeModel = .opus) -> ServiceContainer {
        let products = FakeProductDatabase()
        let appliances = FakeApplianceDatabase()
        return ServiceContainer(
            vision: FakeVisionIdentifier(scene: scene, latency: latency),
            alternatives: FakeAlternativeSuggester(latency: latency),
            researcher: FakeSpecResearcher(latency: latency),
            imageEditor: FakeImageEditor(latency: latency),
            products: products,
            appliances: appliances,
            grid: FakeGridSignal(),
            reference: FakeReferenceStore(),
            plug: FakePlugController(),
            resolvers: [FakeRecordResolver(products: products, appliances: appliances), EstimateResolver()],
            modelChoice: modelChoice,
            isDemo: true)
    }

    /// The container for the current settings. Live network clients slot into their members here as
    /// they are added; members without a live client keep the offline implementation.
    static func make(flags: FeatureFlags, secrets: Secrets) -> ServiceContainer {
        var container = demo(latency: flags.demoMode ? .milliseconds(450) : .zero, modelChoice: flags.modelChoice)
        container.isDemo = flags.demoMode
        container.plug = flags.useMockPlug ? FakePlugController() : nil
        return container
    }

    /// Demo helper: the same services with the identifier replaying a specific canned scene.
    func replaying(_ scene: DemoScene) -> ServiceContainer {
        var copy = self
        copy.vision = FakeVisionIdentifier(scene: scene, latency: isDemo ? .milliseconds(450) : .zero)
        return copy
    }
}
