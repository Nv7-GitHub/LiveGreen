import Foundation

/// Optional `report_components` fields beyond the item facts: where an item's pin goes and what kind of thing it is.
/// They are not required, so an answer without them still decodes, and they decode leniently (`Lenient`), so a
/// malformed one is dropped instead of failing the whole answer. No example names in the descriptions: the fast
/// models copy them.
extension ReportComponentsTool {
    /// Per-component extras, merged into `component`'s properties.
    static let componentExtras: [String: JSONValue] = [
        "anchor": SchemaParts.object([
            "x": SchemaParts.number("Fraction of image width (0-1)."),
            "y": SchemaParts.number("Fraction of image height (0-1, origin top-left)."),
        ], required: ["x", "y"], description: "A point on the item's own visible surface, inside its box, where a marker should sit."),
        "kind": SchemaParts.nullableString("Items other than food and electronics: the plain generic noun for what the item is, lowercase and singular, without brand, colour, size or position words."),
    ]
}

/// Decodes `Value` when it can and nil when it cannot, for optional fields that must never fail a whole answer.
struct Lenient<Value: Decodable & Sendable>: Decodable, Sendable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}
