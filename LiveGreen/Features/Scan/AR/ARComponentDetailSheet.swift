import SwiftUI
import GreenCore
import GreenCoreFakes

/// Detail for a tapped AR label: the component's applicable metrics, with a route into the full scan results.
struct ARComponentDetailSheet: View {
    let component: Component
    let result: ScanResult

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(component.category.applicableMetrics, id: \.self) { metric in
                        row(for: metric)
                    }
                } header: {
                    Label(component.category.displayName, systemImage: component.category.systemImage)
                }
                Section {
                    NavigationLink {
                        ScanResultView(result: result)
                    } label: {
                        Label("Full scan results", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .navigationTitle(component.name)
            .toolbarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private func row(for metric: MetricKey) -> some View {
        HStack {
            Label(metric.displayName, systemImage: metric.systemImage)
            Spacer()
            if let measured = component.metrics[metric] {
                VStack(alignment: .trailing) {
                    Text(measured.formatted).monospacedDigit()
                    Text(measured.formattedRange).font(.caption2).foregroundStyle(.secondary)
                }
                TierBadge(tier: measured.tier)
            } else {
                Text("Not resolved").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let result = SampleScans.preview()
    ARComponentDetailSheet(component: result.components[0], result: result)
        .environment(AppModel.preview())
}
