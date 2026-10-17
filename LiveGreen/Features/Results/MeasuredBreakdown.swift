import GreenCore

/// A labeled part or view of one metric shown under its inspector row, e.g. a plastic mass's item and
/// packaging shares, or a carbon total per year and over the item's life.
struct MeasuredBreakdown: Identifiable, Hashable {
    let label: String
    let measured: Measured

    var id: String { label }

    /// Item vs packaging plastic (spec §4), when the resolver knew the split.
    static func plastic(of component: Component) -> [MeasuredBreakdown] {
        guard let split = component.plasticSplit else { return [] }
        return [MeasuredBreakdown(label: "Item", measured: split.item),
                MeasuredBreakdown(label: "Packaging", measured: split.packaging)]
    }
}
