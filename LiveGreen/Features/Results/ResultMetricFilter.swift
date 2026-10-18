import GreenCore

/// The results metric picker (spec §6): Carbon · Electricity · Water · Land · Plastic · Water pollution · All.
nonisolated enum ResultMetricFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case carbon, electricity, water, land, plastic, pollution, all

    var id: Self { self }

    var title: String {
        switch self {
        case .carbon: "Carbon"
        case .electricity: "Electricity"
        case .water: "Water"
        case .land: "Land"
        case .plastic: "Plastic"
        case .pollution: "Pollution"
        case .all: "All"
        }
    }

    /// The single metric shown, or nil for "All".
    var metric: MetricKey? {
        switch self {
        case .carbon: .carbon
        case .electricity: .yearlyElectricity
        case .water: .water
        case .land: .land
        case .plastic: .plasticMass
        case .pollution: .waterPollution
        case .all: nil
        }
    }

    /// Metric used for hotspot tints and ordering; "All" falls back to carbon.
    var shareMetric: MetricKey { metric ?? .carbon }

    var systemImage: String { metric?.systemImage ?? "square.grid.2x2" }
}
