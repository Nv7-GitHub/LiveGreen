/// Platform-neutral rectangle in normalized 0–1 coordinates of the captured frame,
/// origin at the top-left (matching SwiftUI image space).
public struct NormalizedRect: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { width * height }

    /// Returns the rect clamped into the unit square.
    public var clamped: NormalizedRect {
        let cx = min(max(x, 0), 1), cy = min(max(y, 0), 1)
        return NormalizedRect(x: cx, y: cy, width: min(max(width, 0), 1 - cx), height: min(max(height, 0), 1 - cy))
    }
}
