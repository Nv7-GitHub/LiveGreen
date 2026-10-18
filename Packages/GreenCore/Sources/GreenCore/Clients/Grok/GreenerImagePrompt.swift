import Foundation

/// One chosen swap to paint into the greener-setup picture.
public struct GreenerImageSwap: Sendable, Hashable {
    public var original: String
    public var replacement: String
    public var kind: Alternative.Kind
    public var boundingBox: NormalizedRect?
    /// A second-hand replacement is drawn clean and in good condition, not worn out.
    public var condition: Alternative.Condition

    public init(original: String, replacement: String, kind: Alternative.Kind = .product, boundingBox: NormalizedRect? = nil,
                condition: Alternative.Condition = .new) {
        self.original = original
        self.replacement = replacement
        self.kind = kind
        self.boundingBox = boundingBox
        self.condition = condition
    }
}

/// Builds the image-edit prompt from the chosen swaps (spec §7). The edit is in place (G2 of the image QA): only the
/// named objects change, where they are, and everything else stays as photographed, including every label, logo,
/// person and line of on-screen text. Grok re-drew whole scenes otherwise: another freezer with every pint relabelled,
/// a whole Instagram post, a salad turned into a different meal, used bikes drawn rusty.
public enum GreenerImagePrompt {
    /// Swaps for the alternatives selected in a scan (component id → alternative id) that would show in a photo
    /// (`Alternative.changesTheLook`): not the smart plug, a second-hand copy of the same item or a change of habit,
    /// which would leave the "greener" picture looking like the original. Defaults to the saved `selectedAlternatives`.
    public static func swaps(for result: ScanResult, selection: [UUID: UUID]? = nil) -> [GreenerImageSwap] {
        let selection = selection ?? result.selectedAlternatives
        return result.components.compactMap { component in
            guard let altID = selection[component.id],
                  let alternative = component.alternatives.first(where: { $0.id == altID }),
                  alternative.changesTheLook else { return nil }
            return GreenerImageSwap(original: component.name, replacement: alternative.name, kind: alternative.kind,
                                    boundingBox: component.boundingBox, condition: alternative.condition)
        }
    }

    public static func make(for result: ScanResult) -> String? {
        make(swaps: swaps(for: result))
    }

    /// Nil when there is nothing to change, so no picture is made that would look the same as the photo.
    public static func make(swaps: [GreenerImageSwap]) -> String? {
        guard !swaps.isEmpty else { return nil }
        let edits = swaps.enumerated().map { index, swap in "\(index + 1). \(instruction(for: swap))" }
        return """
            Edit this photo in place. Change only the objects listed here and leave the rest of the image as it is:
            \(edits.joined(separator: "\n"))

            Rules:
            - It is the same photo: same scene, framing, camera angle, lighting, colors and image proportions. Do not \
            re-render, restyle, recompose or crop it.
            - Everything not listed stays exactly as it is: other objects and food, people and hands, furniture and \
            background, and all printed or on-screen text, labels, logos, brand names, usernames and captions.
            - Each replacement sits where the original was, at a realistic size, lit like the rest of the scene, and \
            shows every part its description names (a lid, a straw, a cover).
            - A second-hand or refurbished replacement looks clean and in good condition, never worn, dirty, rusty \
            or damaged.
            - When food is replaced, change only that food: keep the plate or cup, the portion size and every other \
            ingredient as they are.
            - Add no new text, labels, logos, arrows, borders or watermarks. The result must look like an unedited, \
            photorealistic photograph.
            """
    }

    static func instruction(for swap: GreenerImageSwap) -> String {
        let place = swap.boundingBox.map { " (\(region(of: $0)))" } ?? ""
        switch swap.kind {
        case .product:
            var replacement = swap.replacement
            if swap.condition != .new { replacement += ", clean and in good condition" }
            if mentionsLid(swap.replacement) { replacement += ", with its lid on" }
            return "Replace the \(swap.original)\(place) with: \(replacement)."
        case .smartPlugScheduling:
            return "Plug the \(swap.original)\(place) into a small white smart plug at its wall outlet; change nothing else about it."
        }
    }

    /// Image models drew an open tumbler for "steel tumbler with lid" (10, 18, 21).
    static func mentionsLid(_ name: String) -> Bool {
        let words = name.lowercased().split { !$0.isLetter }
        return words.contains("lid") || words.contains("lidded")
    }

    /// Where the object is: its coarse position plus the box's extent in percent, e.g. "left side of the photo,
    /// about 5–30% across and 40–85% down".
    static func region(of box: NormalizedRect) -> String {
        let box = box.clamped
        func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
        return "\(location(of: box)) of the photo, about \(percent(box.x))–\(percent(box.x + box.width))% across and "
            + "\(percent(box.y))–\(percent(box.y + box.height))% down"
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

    /// Where the before/after divider starts (0 = all greener, 1 = all original) so every swapped item is on the
    /// greener side (G3: at 50/50 both swaps sat in the "Before" half): just left of the leftmost swapped box, at most
    /// halfway, at least a sliver of the original. Halfway when no swap has a box.
    public static func revealSplit(for boxes: [NormalizedRect]) -> Double {
        guard let left = boxes.map({ $0.clamped.x }).min() else { return 0.5 }
        return min(max(left - 0.04, 0.06), 0.5)
    }
}
