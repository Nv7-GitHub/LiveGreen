import Foundation

/// `report_components` fields beyond the item facts: whose things the scene shows, where an item's pin goes and what
/// kind of thing it is. All but `scene_context` are optional, so an ordinary photo of the user's own things spends no
/// output on ownership, and every one decodes leniently (`Lenient`): a malformed one is dropped instead of failing the
/// whole answer. No example names in the descriptions: the fast models copy them.
extension ReportComponentsTool {
    /// Top-level extras, merged into the input schema's properties.
    static let sceneExtras: [String: JSONValue] = [
        "scene_context": SchemaParts.enumeration(SceneContext.allCases.map(\.rawValue),
            "Whose things these are: own = the user's home, desk, meal or belongings; store_display = products for sale on shelves or in a display; street = a public place with other people's things; screenshot = a capture of a phone or computer screen."),
    ]

    /// Per-component extras, merged into `component`'s properties.
    static let componentExtras: [String: JSONValue] = [
        "anchor": SchemaParts.object([
            "x": SchemaParts.number("Fraction of image width (0-1)."),
            "y": SchemaParts.number("Fraction of image height (0-1, origin top-left)."),
        ], required: ["x", "y"], description: "A point on the item's own visible surface, inside its box, where a marker should sit."),
        "likely_owned": SchemaParts.nullableBoolean("False when the item is probably not the user's: someone else's, store stock or a display, or a fixture of the place. Omit otherwise."),
        "background": SchemaParts.nullableBoolean("True for an incidental item only partly visible behind or beside what the photo is of. Omit otherwise."),
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
