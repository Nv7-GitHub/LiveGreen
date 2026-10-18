import Foundation

extension ScanPipeline {
    /// Post-processing of the identify output before the ladder runs: plugged-in appliances are scored as
    /// electronics, model names the labels do not back up become model lines, containers reported twice are
    /// counted once, unambiguous on-device hints become identifiers (spec §5.2), and unidentified items get their
    /// generic kind.
    func prepared(_ components: [IdentifiedComponent], hints: OCRHints) -> [IdentifiedComponent] {
        let checked = components.map(reclassified).map { Self.demotingUnreadModel(from: $0, hints: hints) }
        let packaging = Self.countingContainersOnce(checked, store: engine.store ?? .bundled)
        return Self.withGenericKeys(Self.applyingHints(hints, to: packaging))
    }

    /// Reusable dishes are not packaging: a food served in one keeps no packaging mass.
    static let reusableTableware: Set<String> = ["ceramic", "glass_tableware", "stainless_steel"]

    /// A packaging component counts as the food's own packaging when this share of the smaller box overlaps.
    static let containerOverlap = 0.5

    /// A drink's cup is sometimes reported twice: in the drink's `packagingMassG` and as a packaging component of its
    /// own. The food keeps it (so the cup follows the drink's servings a week) and the packaging component is dropped,
    /// lending its materials to foods that did not name theirs. It is a duplicate only when its box mostly overlaps
    /// those foods and its mass is no more than 1.5× theirs; a heavier one (a takeout box under a wrapped burger) is a
    /// different container and stays. Packaging that is only reusable tableware (a ceramic bowl) is cleared first.
    static func countingContainersOnce(_ components: [IdentifiedComponent], store: ReferenceStore) -> [IdentifiedComponent] {
        var result = components
        for index in result.indices where result[index].category == .food {
            let materials = result[index].identifiers.packagingMaterials ?? []
            let tableware = !materials.isEmpty && materials.allSatisfy { share in
                store.materialFactor(material: share.material).map { reusableTableware.contains($0.endOfLife.material) } ?? false
            }
            if tableware {
                result[index].quantities.packagingMassG = nil
                result[index].identifiers.packagingMaterials = []
            }
        }
        var duplicates = Set<Int>()
        for index in result.indices where result[index].category == .packaging {
            let box = result[index].boundingBox
            let holders = result.indices.filter { food in
                result[food].category == .food && (result[food].quantities.packagingMassG ?? 0) > 0
                    && overlap(box, result[food].boundingBox) >= containerOverlap
            }
            let held = holders.reduce(0) { $0 + (result[$1].quantities.packagingMassG ?? 0) }
            let ownG = result[index].quantities.packagingMassG ?? result[index].quantities.massKg.map { $0 * 1000 } ?? 0
            guard !holders.isEmpty, ownG <= held * 1.5 else { continue }
            for food in holders where result[food].identifiers.packagingMaterials?.isEmpty ?? true {
                result[food].identifiers.packagingMaterials = result[index].identifiers.materials
            }
            duplicates.insert(index)
        }
        return result.indices.filter { !duplicates.contains($0) }.map { result[$0] }
    }

    /// Intersection over the smaller box, so a drink inside its cup's box overlaps fully.
    static func overlap(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
        let width = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
        let height = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
        let smaller = min(a.area, b.area)
        guard width > 0, height > 0, smaller > 0 else { return 0 }
        return width * height / smaller
    }

    /// A model the on-device text does not contain was most likely told from the item's look, such as a laptop line
    /// from its keyboard. Looked up as a model number it would match the wrong record and share a cache entry with
    /// other products, so it stays a model only when it looks printed (one word with a digit), identify was highly
    /// confident and its own transcription of the item's text has it. Otherwise it moves to the model line (unless
    /// one is set), without the brand as identify's own lines are, and at most medium confidence: low unless identify
    /// noted the cues it saw. The brand is kept.
    static func demotingUnreadModel(from component: IdentifiedComponent, hints: OCRHints) -> IdentifiedComponent {
        let ids = component.identifiers
        guard let model = ids.model?.trimmedNonEmpty else { return component }
        let key = ReferenceKey.modelKey(model)
        func contains(_ text: String) -> Bool { !key.isEmpty && ReferenceKey.modelKey(text).contains(key) }
        if (hints.modelNumbers + hints.textLines).contains(where: contains) { return component }
        let codeLike = !model.contains(where: \.isWhitespace) && model.contains(where: \.isNumber)
        if codeLike, ids.confidence == .high, ids.ocrText.map(contains) == true { return component }
        var copy = component
        copy.identifiers.model = nil
        if ids.modelLine?.trimmedNonEmpty == nil, let line = Identifiers.modelLine(model, brand: ids.brand) {
            copy.identifiers.modelLine = line
            copy.identifiers.confidence = ids.appearanceCues?.trimmedNonEmpty == nil ? .low
                : ids.confidence.map { $0 == .high ? .medium : $0 }
        }
        return copy
    }

    /// Gives items without a GTIN or brand|model their generic kind, the key they are cached under, so a blue and
    /// a beige backpack resolve alike. Items of one kind in the same scan also share the best-informed one's
    /// category, quantities, materials and fallback estimate: those are guesses that differ from call to call.
    static func withGenericKeys(_ components: [IdentifiedComponent]) -> [IdentifiedComponent] {
        var result = components
        var leads: [String: Int] = [:]
        for index in result.indices where result[index].identifiers.cacheKey == nil {
            guard let key = Identifiers.genericKey(name: result[index].name, category: result[index].category,
                                                   brand: result[index].identifiers.brand) else { continue }
            result[index].identifiers.genericKey = key
            if leads[key].map({ detail(of: result[index]) > detail(of: result[$0]) }) ?? true { leads[key] = index }
        }
        for index in result.indices {
            guard let key = result[index].identifiers.genericKey, let lead = leads[key], lead != index else { continue }
            result[index].category = result[lead].category
            result[index].quantities = result[lead].quantities
            result[index].identifiers.materials = result[lead].identifiers.materials
            result[index].identifiers.packagingMaterials = result[lead].identifiers.packagingMaterials
            result[index].estimates = result[lead].estimates
        }
        return result
    }

    /// How much the factor model has to go on: materials matter most, then a mass.
    private static func detail(of component: IdentifiedComponent) -> Int {
        (component.identifiers.materials.isEmpty ? 0 : 2) + (component.quantities.massKg == nil ? 0 : 1)
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
