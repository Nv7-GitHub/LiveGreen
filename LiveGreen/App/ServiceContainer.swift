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
    var reference: ReferenceStore
    /// The mock plug when the Settings toggle is on; paired plugs live in `PlugCenter`.
    var plug: (any PlugController)?
    /// Evidence-ladder resolvers, any order (the ladder sorts by tier).
    var resolvers: [any MetricResolver]
    var modelChoice: ClaudeModel
    var isDemo: Bool

    /// The ladder of spec §5.4: T1 records (Open Food Facts, ENERGY STAR, ASUS PCF), T2 cited research,
    /// T3 reference factors, T4 bounded estimates.
    static func resolvers(products: any ProductDatabase, appliances: any ApplianceDatabase,
                          researcher: any SpecResearcher, reference: ReferenceStore) -> [any MetricResolver] {
        [OpenFoodFactsResolver(products: products), EnergyStarResolver(appliances: appliances),
         ASUSPCFResolver(store: reference), SpecResearchResolver(researcher: researcher, maxConcurrent: 4),
         FactorModelResolver(store: reference), EstimateResolver()]
    }

    /// Demo mode (spec §11): replays the recorded fixture scenes end to end with no network. Identify,
    /// alternatives, research and the greener image are canned; records, factors and the engine are real.
    static func demo(scene: DemoScene = .deskSetup, latency: Duration = .milliseconds(450),
                     modelChoice: ClaudeModel = .sonnet) -> ServiceContainer {
        let reference = ReferenceStore.bundled
        let products = FakeProductDatabase()
        let appliances = FakeApplianceDatabase()
        let researcher = FakeSpecResearcher(latency: latency)
        return ServiceContainer(
            vision: FakeVisionIdentifier(scene: scene, latency: latency),
            alternatives: FakeAlternativeSuggester(latency: latency),
            researcher: researcher,
            imageEditor: DemoImageEditor(latency: latency * 3),
            products: products,
            appliances: appliances,
            grid: BundledGridSignal(store: reference),
            reference: reference,
            plug: PlugConnector.live.mock,
            resolvers: resolvers(products: products, appliances: appliances, researcher: researcher, reference: reference),
            modelChoice: modelChoice,
            isDemo: true)
    }

    /// Live services. Keyless clients (Open Food Facts, ENERGY STAR, EIA grid data) always run; an Electricity
    /// Maps key switches the grid to Electricity Maps. Analysis and image calls without a key throw
    /// `missingAPIKey`, which the ladder skips and the scan and image screens report (Settings names the key).
    static func live(flags: FeatureFlags, secrets: Secrets) -> ServiceContainer {
        let reference = ReferenceStore.bundled
        let analysis = analysisClient(flags: flags, secrets: secrets, vocabulary: reference.vocabulary)
        let products = OpenFoodFactsClient()
        let appliances = EnergyStarClient(appToken: secrets.value(for: .energyStar))
        let grid: any GridSignal = secrets.value(for: .electricityMaps).map { ElectricityMapsClient(apiKey: $0) }
            ?? EIAGridClient()
        return ServiceContainer(
            vision: analysis,
            alternatives: analysis,
            researcher: analysis,
            imageEditor: GrokImageClient(apiKey: secrets.value(for: .xai)),
            products: products,
            appliances: appliances,
            grid: grid,
            reference: reference,
            plug: flags.useMockPlug ? PlugConnector.live.mock : nil,
            resolvers: resolvers(products: products, appliances: appliances, researcher: analysis, reference: reference),
            modelChoice: flags.modelChoice,
            isDemo: false)
    }

    /// Identify, alternatives and spec research from the provider picked in Settings.
    static func analysisClient(flags: FeatureFlags, secrets: Secrets,
                               vocabulary: ReferenceVocabulary) -> any VisionIdentifier & AlternativeSuggester & SpecResearcher {
        switch flags.aiProvider {
        case .grok:
            GrokAnalysisClient(configuration: .init(apiKey: secrets.value(for: .xai), vocabulary: vocabulary))
        case .claude:
            ClaudeClient(configuration: .init(apiKey: secrets.value(for: .anthropic),
                                              workspaceID: secrets.value(for: .anthropicWorkspace), model: flags.modelChoice,
                                              vocabulary: vocabulary))
        }
    }

    /// The container for the current settings.
    static func make(flags: FeatureFlags, secrets: Secrets) -> ServiceContainer {
        flags.demoMode ? demo(modelChoice: flags.modelChoice) : live(flags: flags, secrets: secrets)
    }

    /// Demo helper: the same services with the identifier replaying a specific canned scene.
    func replaying(_ scene: DemoScene) -> ServiceContainer {
        var copy = self
        copy.vision = FakeVisionIdentifier(scene: scene, latency: isDemo ? .milliseconds(450) : .zero)
        return copy
    }

    /// The scan pipeline over these services.
    func pipeline(profile: UserProfile, cache: (any ResolutionCache)?) -> ScanPipeline {
        ScanPipeline(vision: vision, alternatives: alternatives, products: products,
                     ladder: EvidenceLadder(resolvers: resolvers, cache: cache),
                     engine: ImpactEngine(reference: reference), profile: profile)
    }
}
