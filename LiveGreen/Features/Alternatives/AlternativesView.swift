import SwiftUI
import GreenCore
import GreenCoreFakes

/// Greener swaps per component (spec §7), resolved through the same ladder as the originals.
struct AlternativesView: View {
    let result: ScanResult
    @Environment(AppModel.self) private var model
    @State private var updated: ScanResult?
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger)
            }
            ForEach((updated ?? result).components) { component in
                Section(component.name) {
                    if component.alternatives.isEmpty && updated == nil {
                        ProgressView()
                    }
                    ForEach(component.alternatives) { alternative in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alternative.name).font(.headline)
                            Text(alternative.rationale).font(.footnote).foregroundStyle(.secondary)
                            if let before = component.metrics[.carbon], let after = alternative.metrics[.carbon], before.value > 0 {
                                let better = (1 - after.value / before.value) * 100
                                Text("\(Int(better.rounded()))% less carbon")
                                    .font(.caption.bold())
                                    .foregroundStyle(Theme.leaf)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Greener swaps")
        .task {
            guard updated == nil else { return }
            do {
                let resolved = try await model.makeScanCoordinator().suggestAlternatives(for: result)
                updated = resolved
                model.save(resolved)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack { AlternativesView(result: SampleScans.preview()) }.environment(AppModel.preview())
}
