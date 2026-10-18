import Testing
@testable import GreenCore

@Suite("Results pins: de-overlap and absolute impact levels")
struct PinLayoutTests {
    private let photo = SIMD2<Double>(360, 480)

    private func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        ((a - b) * (a - b)).sum().squareRoot()
    }

    @Test func pinsOnOneBoxEndUpSideBySide() throws {
        // A drink and its cup share one box (19, 20, 28): the top item's pin must not hide under the other.
        let anchor = SIMD2<Double>(200, 120)
        let pins = PinLayout.spread([anchor, anchor], spacing: 36, in: photo, inset: 17)
        #expect(distance(pins[0], pins[1]) >= 36 - 1e-6)
        #expect(pins[0].x < pins[1].x)
        // The first, more important pin stays nearer its item.
        #expect(distance(pins[0], anchor) < distance(pins[1], anchor))
    }

    @Test func separatePinsStayOnTheirItems() {
        let anchors: [SIMD2<Double>] = [[60, 60], [300, 400], [180, 240]]
        #expect(PinLayout.spread(anchors, spacing: 36, in: photo, inset: 17) == anchors)
    }

    @Test func aStackedColumnSpreadsInsideThePhoto() {
        // Three full-plate boxes whose centres fall in one column (27), one of them at the edge.
        let anchors: [SIMD2<Double>] = [[180, 300], [171, 264], [180, 288], [355, 470]]
        let pins = PinLayout.spread(anchors, spacing: 36, in: photo, inset: 17)
        for i in pins.indices {
            #expect(pins[i].x >= 17 && pins[i].x <= photo.x - 17)
            #expect(pins[i].y >= 17 && pins[i].y <= photo.y - 17)
            for j in pins.indices where j > i { #expect(distance(pins[i], pins[j]) >= 36 - 0.5) }
        }
        #expect(PinLayout.spread(anchors, spacing: 36, in: photo, inset: 17) == pins)
    }

    @Test func levelsFollowAbsoluteYearlyAmounts() {
        // A 3 g flyer once a week is low however much of its scene it is; a car's embodied carbon is very high.
        #expect(ImpactLevel(yearly: 0.17, metric: .carbon) == .low)
        #expect(ImpactLevel(yearly: 72, metric: .carbon) == .moderate)
        #expect(ImpactLevel(yearly: 154, metric: .carbon) == .high)
        #expect(ImpactLevel(yearly: 938, metric: .carbon) == .veryHigh)
        #expect(ImpactLevel(yearly: 37, metric: .yearlyElectricity) == .moderate)
        #expect(ImpactLevel(yearly: 5, metric: .lifespan) == nil)
        #expect(ImpactLevel.allCases.sorted() == [.low, .moderate, .high, .veryHigh])
    }
}
