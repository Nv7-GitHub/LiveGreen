import SwiftUI
import UIKit
import GreenCore
import GreenCoreFakes

/// Fake, fully resolved alternatives for SwiftUI previews.
enum AlternativesPreviewData {
    /// The desk scene with two product swaps per component plus the plug option on the laptop.
    static let result: ScanResult = {
        var scan = SampleScans.preview(.deskSetup)
        scan.photo = photo(tint: .brown)
        for index in scan.components.indices {
            let component = scan.components[index]
            var options = [
                swap(component, name: "Refurbished \(component.name.lowercased())", factor: 0.55,
                     rationale: "Refurbished avoids most manufacturing emissions.",
                     practicality: Practicality(cost: .lower, effort: .easy)),
                swap(component, name: "Efficient \(component.name.lowercased())", factor: 0.8,
                     rationale: "A newer model that draws less power.",
                     practicality: Practicality(cost: .higher, effort: .moderate)),
            ]
            if let candidate = component.plugCandidate {
                let savings = Measured(value: 6, relativeRange: 0.3, unit: .kgCO2e, tier: .factorModel,
                                       sources: [Source(title: "Preview grid shape", tier: .factorModel)])
                scan.components[index].plugCandidate = PlugCandidate(loadType: candidate.loadType,
                                                                     chargerWatts: candidate.chargerWatts,
                                                                     dailyKWh: candidate.dailyKWh, estimatedSavings: savings)
                options.append(SmartPlugAlternative.make(for: scan.components[index]))
            }
            scan.components[index].alternatives = options
        }
        return scan
    }()

    /// Charging comparison for the plug option in previews.
    static let charging: SmartPlugAlternative.ChargingCarbon = {
        let source = [Source(title: "Preview grid shape", tier: .factorModel)]
        return SmartPlugAlternative.ChargingCarbon(
            current: Measured(value: 22, relativeRange: 0.3, unit: .kgCO2e, tier: .factorModel, sources: source),
            scheduled: Measured(value: 16, relativeRange: 0.3, unit: .kgCO2e, tier: .factorModel, sources: source),
            savings: Measured(value: 6, relativeRange: 0.3, unit: .kgCO2e, tier: .factorModel, sources: source))
    }()

    private static func swap(_ component: Component, name: String, factor: Double, rationale: String,
                             practicality: Practicality) -> Alternative {
        var metrics: [MetricKey: Measured] = [:]
        for (metric, measured) in component.metrics {
            let scale = metric.higherIsBetter ? 1 / factor : factor
            let capped = metric == .recyclablePercent ? min(measured.value * scale, 100) : measured.value * scale
            metrics[metric] = Measured(value: capped, low: min(measured.low * scale, capped),
                                       high: metric == .recyclablePercent ? min(measured.high * scale, 100) : measured.high * scale,
                                       unit: measured.unit, tier: measured.tier, sources: measured.sources)
        }
        return Alternative(name: name, category: component.category, usage: component.usage, rationale: rationale,
                           practicality: practicality, metrics: metrics)
    }

    /// A simple rendered "room" JPEG so the image views have something to show.
    static func photo(tint: UIColor) -> Data {
        let size = CGSize(width: 800, height: 600)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            tint.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.35).setFill()
            context.fill(CGRect(x: 0, y: 380, width: 800, height: 220))
            tint.setFill()
            context.fill(CGRect(x: 240, y: 270, width: 320, height: 120))
            context.fill(CGRect(x: 200, y: 50, width: 400, height: 200))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}
