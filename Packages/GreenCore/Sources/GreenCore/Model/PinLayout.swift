/// Where to draw numbered pins over a photo (spec §6) so none hides another. Each pin starts at its anchor, an item's
/// box centre (identify gives no point of its own), and overlapping pins are pushed apart, earlier pins less, then
/// kept inside the photo. Two items with one box (a drink and its cup) end up side by side instead of stacked.
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
