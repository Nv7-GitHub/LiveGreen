import Foundation
import GreenCore

/// Edit prompt for the greener-setup picture, built from the chosen swaps (spec §7).
nonisolated enum GreenerImagePrompt {
    struct Swap: Hashable {
        var original: String
        var replacement: String
        var kind: Alternative.Kind
        var box: NormalizedRect
    }

    static func swaps(in result: ScanResult, selection: [UUID: UUID]) -> [Swap] {
        result.components.compactMap { component in
            guard let id = selection[component.id],
                  let pick = component.alternatives.first(where: { $0.id == id }) else { return nil }
            return Swap(original: component.name, replacement: pick.name, kind: pick.kind, box: component.boundingBox)
        }
    }

    static func make(for swaps: [Swap]) -> String {
        let lines = swaps.enumerated().map { index, swap in
            switch swap.kind {
            case .product:
                "\(index + 1). Replace the \(swap.original) (\(location(of: swap.box))) with a \(swap.replacement), same size and position."
            case .smartPlugScheduling:
                "\(index + 1). Keep the \(swap.original) (\(location(of: swap.box))) and plug it into a small white smart plug at the wall outlet."
            }
        }
        return """
        Edit this photo to show a greener version of the same scene.
        \(lines.joined(separator: "\n"))
        Keep everything else exactly as it is: the room, lighting, layout, camera angle and all other objects. \
        Each replacement sits where the original was. The result must look like an unedited, photorealistic photo.
        """
    }

    /// Plain-language position of a normalized box, e.g. "upper left of the frame".
    static func location(of box: NormalizedRect) -> String {
        let vertical = box.midY < 0.34 ? "upper" : box.midY > 0.66 ? "lower" : "middle"
        let horizontal = box.midX < 0.34 ? "left" : box.midX > 0.66 ? "right" : "center"
        if vertical == "middle" && horizontal == "center" { return "center of the frame" }
        return "\(vertical) \(horizontal) of the frame"
    }
}
