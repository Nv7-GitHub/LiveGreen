import GreenCore

/// A labeled part or view of one metric shown under its inspector row, e.g. a plastic mass's item and
/// packaging shares, or a carbon total per year and over the item's life.
struct MeasuredBreakdown: Identifiable, Hashable {
    let label: String
    let measured: Measured

    var id: String { label }

    /// Carbon per year and, for durables, over the item's life (spec §5.6).
    static func carbon(of component: Component, engine: ImpactEngine) -> [MeasuredBreakdown] {
        guard let views = engine.carbonViews(of: component) else { return [] }
        var parts = [MeasuredBreakdown(label: "Per year", measured: views.perYear)]
        if let lifetime = views.lifetime {
            parts.append(MeasuredBreakdown(label: "Lifetime", measured: lifetime))
        } else {
            parts.append(MeasuredBreakdown(label: component.basisTitle ?? "Per unit", measured: views.perUnit))
        }
        return parts
    }

    /// Item vs packaging plastic (spec §4), when the resolver knew the split and both parts have some
    /// plastic; "Packaging 0 g" says nothing the row does not.
    static func plastic(of component: Component) -> [MeasuredBreakdown] {
        guard let split = component.plasticSplit,
              !split.item.isEffectivelyZero, !split.packaging.isEffectivelyZero else { return [] }
        return [MeasuredBreakdown(label: "Item", measured: split.item),
                MeasuredBreakdown(label: "Packaging", measured: split.packaging)]
    }
}
