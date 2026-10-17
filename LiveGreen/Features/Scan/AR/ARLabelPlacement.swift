import CoreGraphics
import Foundation

/// Screen-space layout for the AR labels: each label sits just above its pin, but labels never overlap each
/// other and stay inside `bounds` (the band between the top bar and the bottom controls). A label that has to
/// move is slid to the nearest free spot; the pin keeps a leader line to it. A label with no free spot nearby
/// is left out (its item stays reachable from the Items menu) rather than drawn over another label.
nonisolated enum ARLabelPlacement {
    struct Item: Equatable {
        let id: UUID
        /// Projected pin position.
        let anchor: CGPoint
        let size: CGSize
        /// Higher priority labels are placed first and keep their preferred spot (the biggest carbon share).
        let priority: Double
    }

    /// Gap above the pin to the label's center.
    static let lift: CGFloat = 34
    /// Minimum space kept between two labels.
    static let gap: CGFloat = 6

    static func frames(for items: [Item], in bounds: CGRect) -> [UUID: CGRect] {
        let ordered = items.sorted {
            $0.priority != $1.priority ? $0.priority > $1.priority : $0.id.uuidString < $1.id.uuidString
        }
        var placed: [UUID: CGRect] = [:]
        for item in ordered {
            let preferred = CGRect(x: item.anchor.x - item.size.width / 2,
                                   y: item.anchor.y - lift - item.size.height / 2,
                                   width: item.size.width, height: item.size.height)
            let free = offsets(for: item.size).lazy
                .map { clamp(preferred.offsetBy(dx: $0.dx, dy: $0.dy), into: bounds) }
                .first { candidate in
                    !placed.values.contains { $0.insetBy(dx: -gap, dy: -gap).intersects(candidate) }
                }
            if let free { placed[item.id] = free }
        }
        return placed
    }

    /// Nearby slots, nearest first: whole label heights up and down (up wins ties, since labels read as
    /// sitting above their pins), and half or a whole label width to either side.
    private static func offsets(for size: CGSize) -> [CGVector] {
        let dys = (-3...3).map { CGFloat($0) * (size.height + gap) }
        let dxs = [0, -0.5, 0.5, -1, 1].map { $0 * (size.width + gap) }
        return dys.flatMap { dy in dxs.map { CGVector(dx: $0, dy: dy) } }
            .enumerated()
            .sorted { a, b in
                let da = hypot(a.element.dx, a.element.dy), db = hypot(b.element.dx, b.element.dy)
                return da != db ? da < db : a.offset < b.offset
            }
            .map(\.element)
    }

    /// Point on `rect`'s edge closest to `point`, where a leader line from the pin should end.
    static func leaderEnd(from point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
    }

    private static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var rect = rect
        rect.origin.x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - rect.width))
        rect.origin.y = min(max(rect.minY, bounds.minY), max(bounds.minY, bounds.maxY - rect.height))
        return rect
    }
}
