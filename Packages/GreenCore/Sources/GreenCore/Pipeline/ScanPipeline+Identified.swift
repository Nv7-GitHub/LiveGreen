import Foundation

extension ScanPipeline {
    /// Post-processing of the identify output before the ladder runs: plugged-in appliances are scored as
    /// electronics, model names the labels do not back up are dropped, unambiguous on-device hints become
    /// identifiers (spec §5.2), and unidentified items get their generic kind.
    func prepared(_ components: [IdentifiedComponent], hints: OCRHints) -> [IdentifiedComponent] {
        let checked = components.map(reclassified).map { Self.droppingUnreadModel(from: $0, hints: hints) }
        return Self.withGenericKeys(Self.applyingHints(hints, to: checked))
    }

    /// A model the on-device text does not contain and that is not a printed-looking code (one word with a
    /// digit) was most likely inferred from the item's look, such as a product line guessed from a shoe's shape.
    /// Looking it up would score the wrong product, so it is dropped; the brand is kept.
    static func droppingUnreadModel(from component: IdentifiedComponent, hints: OCRHints) -> IdentifiedComponent {
        guard let model = component.identifiers.model?.trimmedNonEmpty else { return component }
        let key = ReferenceKey.modelKey(model)
        let read = !key.isEmpty && (hints.modelNumbers + hints.textLines).contains { ReferenceKey.modelKey($0).contains(key) }
        let codeLike = !model.contains(where: \.isWhitespace) && model.contains(where: \.isNumber)
        guard !read, !codeLike else { return component }
        var copy = component
        copy.identifiers.model = nil
        return copy
    }

    /// Gives items without a GTIN or brand|model their generic kind, the key they are cached under, so a blue and
    /// a beige backpack resolve alike. Items of one kind in the same scan also share the first one's category,
    /// quantities, materials and fallback estimate: those are guesses that differ from call to call.
    static func withGenericKeys(_ components: [IdentifiedComponent]) -> [IdentifiedComponent] {
        var result = components
        var leads: [String: Int] = [:]
        for index in result.indices where result[index].identifiers.cacheKey == nil {
            guard let key = Identifiers.genericKey(name: result[index].name, category: result[index].category) else { continue }
            result[index].identifiers.genericKey = key
            guard let lead = leads[key] else {
                leads[key] = index
                continue
            }
            result[index].category = result[lead].category
            result[index].quantities = result[lead].quantities
            result[index].identifiers.materials = result[lead].identifiers.materials
            result[index].estimates = result[lead].estimates
        }
        return result
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
