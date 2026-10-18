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

extension NormalizedRect {
    /// This rect in the coordinates of `region` (both normalized to the same frame), clamped into it: where the box
    /// sits once the photo is cropped to `region`.
    public func relative(to region: NormalizedRect) -> NormalizedRect {
        guard region.width > 0, region.height > 0 else { return self }
        return NormalizedRect(x: (x - region.x) / region.width, y: (y - region.y) / region.height,
                              width: width / region.width, height: height / region.height).clamped
    }

    public func contains(_ point: NormalizedPoint) -> Bool {
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }
}

/// A point in normalized 0–1 coordinates of the captured frame, origin at the top-left.
public struct NormalizedPoint: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The point clamped into the unit square.
    public var clamped: NormalizedPoint { NormalizedPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1)) }

    /// This point in the coordinates of `region`, clamped into it.
    public func relative(to region: NormalizedRect) -> NormalizedPoint {
        guard region.width > 0, region.height > 0 else { return self }
        return NormalizedPoint(x: (x - region.x) / region.width, y: (y - region.y) / region.height).clamped
    }
}
