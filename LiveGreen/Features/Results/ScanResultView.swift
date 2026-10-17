import SwiftUI
import GreenCore
import GreenCoreFakes

/// Results for one scan (spec §6): totals header, components and their metrics with tier badges.
struct ScanResultView: View {
    let result: ScanResult

    var body: some View {
        List {
            Section("Totals") {
                ForEach(ScanTotals.additiveMetrics, id: \.self) { metric in
                    if let measured = result.totals[metric] { MetricLine(metric: metric, measured: measured) }
                }
            }
            ForEach(result.components) { component in
                Section {
                    ForEach(component.category.applicableMetrics, id: \.self) { metric in
                        if let measured = component.metrics[metric] { MetricLine(metric: metric, measured: measured) }
                    }
                } header: {
                    Label(component.name, systemImage: component.category.systemImage)
                }
            }
        }
        .navigationTitle(result.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AlternativesView(result: result)
                } label: {
                    Label("Greener swaps", systemImage: "leaf.arrow.triangle.circlepath")
                }
            }
        }
    }
}

/// One metric row: name, value, range and tier.
private struct MetricLine: View {
    let metric: MetricKey
    let measured: Measured

    var body: some View {
        HStack {
            Label(metric.displayName, systemImage: metric.systemImage)
            Spacer()
            VStack(alignment: .trailing) {
                Text(measured.formatted).monospacedDigit()
                Text(measured.formattedRange).font(.caption2).foregroundStyle(.secondary)
            }
            TierBadge(tier: measured.tier)
        }
    }
}

#Preview {
    NavigationStack { ScanResultView(result: SampleScans.preview()) }
}
