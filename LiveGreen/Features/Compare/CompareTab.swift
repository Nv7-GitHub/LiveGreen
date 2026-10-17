import SwiftUI
import GreenCore

/// Peer comparison and percentiles (spec §9).
struct CompareTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section("Scanned footprint") {
                    let totals = ScanTotals.sum(model.scans.flatMap(\.components))
                    if totals.isEmpty {
                        Text("Scan items to compare yourself with people like you.").foregroundStyle(.secondary)
                    }
                    ForEach(ScanTotals.additiveMetrics, id: \.self) { metric in
                        if let total = totals[metric] {
                            LabeledContent(metric.displayName, value: total.formatted)
                        }
                    }
                }
            }
            .navigationTitle("Compare")
            .settingsToolbarButton()
        }
    }
}

#Preview {
    CompareTab().environment(AppModel.preview())
}
