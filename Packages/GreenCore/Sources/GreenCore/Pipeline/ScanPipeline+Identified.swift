import Foundation

extension ScanPipeline {
    /// Post-processing of the identify output before the ladder runs: plugged-in appliances are scored as
    /// electronics, and unambiguous on-device hints become identifiers (spec §5.2).
    func prepared(_ components: [IdentifiedComponent], hints: OCRHints) -> [IdentifiedComponent] {
        Self.applyingHints(hints, to: components.map(reclassified))
    }

    /// A `household` item with a known powered device type (dishwasher, kettle…) is an electronic, so it gets
    /// power and electricity metrics, ENERGY STAR records and the smart-plug option.
    func reclassified(_ component: IdentifiedComponent) -> IdentifiedComponent {
        guard component.category == .household, let type = component.quantities.deviceType,
              engine.store?.deviceProfile(deviceType: type) != nil else { return component }
        var copy = component
        copy.category = .electronic
        return copy
    }

    /// Fills identifiers the model left empty from hints that can only belong to one component: a single GTIN
    /// on the single packaged item, and a single model number or wattage on the single electronic. Fiber
    /// percentages from a care label go to the single garment.
    static func applyingHints(_ hints: OCRHints, to components: [IdentifiedComponent]) -> [IdentifiedComponent] {
        var result = components
        let packaged: Set<Category> = [.food, .packaging, .personalCare]
        if hints.gtins.count == 1, let gtin = hints.gtins.first,
           !result.contains(where: { $0.identifiers.gtin == gtin }),
           let index = soleIndex(in: result, where: { packaged.contains($0.category) }),
           result[index].identifiers.gtin?.isEmpty ?? true {
            result[index].identifiers.gtin = gtin
        }
        if let index = soleIndex(in: result, where: { $0.category == .electronic }) {
            if hints.modelNumbers.count == 1, result[index].identifiers.model?.isEmpty ?? true {
                result[index].identifiers.model = hints.modelNumbers[0]
            }
            if hints.wattages.count == 1, result[index].quantities.ratedPowerW == nil {
                result[index].quantities.ratedPowerW = hints.wattages[0]
            }
        }
        if !hints.fiberPercentages.isEmpty, let index = soleIndex(in: result, where: { $0.category == .clothing }),
           result[index].identifiers.materials.isEmpty {
            result[index].identifiers.materials = hints.fiberPercentages
        }
        return result
    }

    private static func soleIndex(in components: [IdentifiedComponent],
                                  where matches: (IdentifiedComponent) -> Bool) -> Int? {
        let indices = components.indices.filter { matches(components[$0]) }
        return indices.count == 1 ? indices[0] : nil
    }
}
