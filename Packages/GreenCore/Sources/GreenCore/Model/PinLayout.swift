/// Where to draw numbered pins over a photo (spec §6) so none hides another. Each pin starts at its anchor
/// (`anchor(box:point:)`: identify's point on the item, else the box centre), and overlapping pins are pushed apart,
/// earlier pins less, then kept inside the photo. Two items with one box (a drink and its cup) end up side by side instead of stacked.
/// Deterministic, so pins sit in the same place on every render.
public enum PinLayout {
    /// Pin centres for `anchors` (points in a `size` photo, most important first), at least `spacing` apart where
    /// the photo leaves room and at least `inset` from its edges.
    public static func spread(_ anchors: [SIMD2<Double>], spacing: Double, in size: SIMD2<Double>,
                              inset: Double, iterations: Int = 80) -> [SIMD2<Double>] {
        let lower = SIMD2(repeating: inset)
        let upper = SIMD2(Swift.max(size.x - inset, inset), Swift.max(size.y - inset, inset))
        func clamped(_ point: SIMD2<Double>) -> SIMD2<Double> { point.clamped(lowerBound: lower, upperBound: upper) }

        var points = anchors.map(clamped)
        guard points.count > 1, spacing > 0 else { return points }
        for _ in 0..<iterations {
            var moved = false
            for i in points.indices {
                for j in points.indices where j > i {
                    let delta = points[j] - points[i]
                    let distance = (delta * delta).sum().squareRoot()
                    guard distance < spacing - 1e-6 else { continue }
                    // On the same spot, side by side with the later pin to the right.
                    let direction = distance > 1e-6 ? delta / distance : SIMD2(1, 0)
                    let overlap = spacing - distance
                    // The earlier, more important pin moves a third of the way, so it stays nearer its item.
                    points[i] -= direction * (overlap / 3)
                    points[j] += direction * (overlap * 2 / 3)
                    moved = true
                }
            }
            points = points.map(clamped)
            if !moved { break }
        }
        return points
    }
}

extension PinLayout {
    /// How far outside its box identify's point may lie and still count as on the item: this share of the box's
    /// width or height, at least `minimumSlack` of the photo.
    static let anchorSlack = 0.25
    static let minimumSlack = 0.03

    /// Where an item's pin points, normalized: identify's point on the item when it lies in or near the box, since a
    /// point lands on a small item where a loose box's centre can miss it; else the box centre. A point far from its
    /// box is more likely a slip than a better guess.
    public static func anchor(box: NormalizedRect, point: NormalizedPoint?) -> NormalizedPoint {
        let box = box.clamped
        let centre = NormalizedPoint(x: box.midX, y: box.midY)
        guard let point = point?.clamped else { return centre }
        let dx = max(box.width * anchorSlack, minimumSlack), dy = max(box.height * anchorSlack, minimumSlack)
        let near = NormalizedRect(x: box.x - dx, y: box.y - dy, width: box.width + 2 * dx, height: box.height + 2 * dy)
        return near.contains(point) ? point : centre
    }
}

extension Component {
    /// Where the item's pin points on the photo (`PinLayout.anchor(box:point:)`).
    public var pinAnchor: NormalizedPoint { PinLayout.anchor(box: boundingBox, point: anchor) }
}
