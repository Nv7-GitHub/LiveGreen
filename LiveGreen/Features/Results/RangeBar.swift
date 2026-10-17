import SwiftUI
import GreenCore

/// Uncertainty bar: the low–high range as a tier-colored capsule with a dot at the value.
struct RangeBar: View {
    let measured: Measured

    /// Scale shown by the bar. Bounded units use their natural scale; others leave headroom past `high`.
    private var domain: ClosedRange<Double> {
        switch measured.unit {
        case .percent: return 0...100
        case .score10: return 0...10
        default:
            let lower = min(0, measured.low)
            let upper = max(measured.high * 1.15, measured.value, lower + 1e-9)
            return lower...upper
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let lowX = position(measured.low, width: width)
            let highX = position(measured.high, width: width)
            let valueX = position(measured.value, width: width)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(measured.tier.color.opacity(0.45))
                    .frame(width: max(6, highX - lowX))
                    .offset(x: min(lowX, width - 6))
                Circle()
                    .fill(measured.tier.color)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .offset(x: min(max(valueX - 5, 0), width - 10))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func position(_ value: Double, width: CGFloat) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0 }
        let clamped = min(max(value, domain.lowerBound), domain.upperBound)
        return CGFloat((clamped - domain.lowerBound) / span) * width
    }
}
