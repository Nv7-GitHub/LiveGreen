import Foundation

/// One chosen swap to paint into the greener-setup picture.
public struct GreenerImageSwap: Sendable, Hashable {
    public var original: String
    public var replacement: String
    public var kind: Alternative.Kind
    public var boundingBox: NormalizedRect?

    public init(original: String, replacement: String, kind: Alternative.Kind = .product, boundingBox: NormalizedRect? = nil) {
        self.original = original
        self.replacement = replacement
        self.kind = kind
        self.boundingBox = boundingBox
    }
}

/// Builds the image-edit prompt from the chosen swaps (spec §7): replace each object where it is and
/// keep everything else — lighting, layout, camera angle — unchanged and photorealistic.
public enum GreenerImagePrompt {
    /// Swaps for the alternatives selected in a scan (component id → alternative id). Defaults to the scan's
    /// saved `selectedAlternatives`.
    public static func swaps(for result: ScanResult, selection: [UUID: UUID]? = nil) -> [GreenerImageSwap] {
        let selection = selection ?? result.selectedAlternatives
        return result.components.compactMap { component in
            guard let altID = selection[component.id],
                  let alternative = component.alternatives.first(where: { $0.id == altID }) else { return nil }
            return GreenerImageSwap(original: component.name, replacement: alternative.name, kind: alternative.kind,
                                    boundingBox: component.boundingBox)
        }
    }

    public static func make(for result: ScanResult) -> String? {
        make(swaps: swaps(for: result))
    }

    /// Nil when there is nothing to change.
    public static func make(swaps: [GreenerImageSwap]) -> String? {
        guard !swaps.isEmpty else { return nil }
        let edits = swaps.enumerated().map { index, swap in "\(index + 1). \(instruction(for: swap))" }
        return """
            Edit this photo to show the same scene with greener choices. Make only these changes:
            \(edits.joined(separator: "\n"))

            Keep everything else exactly as it is: the room, furniture, other objects, layout, lighting, shadows, \
            colors, camera angle, framing and image proportions. Each replacement sits in the same place as the \
            object it replaces, at a realistic size, lit consistently with the scene. The result must look like \
            an unedited, photorealistic photograph: no text, labels, logos, arrows, borders or watermarks.
            """
    }

    static func instruction(for swap: GreenerImageSwap) -> String {
        let place = swap.boundingBox.map { " (\(location(of: $0)) of the photo)" } ?? ""
        switch swap.kind {
        case .product:
            return "Replace the \(swap.original)\(place) with: \(swap.replacement)."
        case .smartPlugScheduling:
            return "Plug the \(swap.original)\(place) into a small white smart plug at its wall outlet; change nothing else about it."
        }
    }

    /// Coarse 3×3 position name for a normalized box center, e.g. "upper left", "center".
    static func location(of box: NormalizedRect) -> String {
        let vertical = box.midY < 1.0 / 3 ? "upper" : (box.midY > 2.0 / 3 ? "lower" : "middle")
        let horizontal = box.midX < 1.0 / 3 ? "left" : (box.midX > 2.0 / 3 ? "right" : "center")
        switch (vertical, horizontal) {
        case ("middle", "center"): return "center"
        case ("middle", _): return horizontal == "left" ? "left side" : "right side"
        case (_, "center"): return "\(vertical) center"
        default: return "\(vertical) \(horizontal)"
        }
    }
}
