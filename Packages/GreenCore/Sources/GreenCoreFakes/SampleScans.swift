import Foundation
import GreenCore

/// Fully resolved sample results for SwiftUI previews and UI tests.
public enum SampleScans {
    /// A demo scene resolved through the demo record databases (T1), then T4 estimates.
    public static func resolved(_ scene: DemoScene = .deskSetup, profile: UserProfile = .default) async -> ScanResult {
        let ladder = EvidenceLadder(resolvers: demoRecordResolvers + [EstimateResolver()])
        var components: [Component] = []
        for identified in scene.identifyResponse.components {
            components.append(await ladder.resolve(identified.makeComponent(), profile: profile))
        }
        return ScanResult(title: scene.title, components: components, totals: ScanTotals.sum(components))
    }

    /// The real T1 resolvers over the in-memory demo databases.
    public static var demoRecordResolvers: [any MetricResolver] {
        [OpenFoodFactsResolver(products: FakeProductDatabase()), EnergyStarResolver(appliances: FakeApplianceDatabase())]
    }

    /// Synchronous variant for previews: estimates only (T4), no async resolution needed.
    public static func preview(_ scene: DemoScene = .deskSetup) -> ScanResult {
        let components = scene.identifyResponse.components.map { identified -> Component in
            var component = identified.makeComponent()
            for (metric, estimate) in identified.estimates {
                component.metrics[metric] = Measured(value: estimate.value, low: estimate.low, high: estimate.high,
                                                     unit: metric.unit, tier: .estimate,
                                                     sources: [Source(title: "Sample estimate", tier: .estimate)])
            }
            return component
        }
        return ScanResult(title: scene.title, components: components, totals: ScanTotals.sum(components))
    }
}
