import SwiftUI
import GreenCore
import GreenCoreFakes

/// Detail for a tapped AR label (spec §5.1): the same component detail the Results screen shows (flow,
/// inspector with sources, plug card), with a route into the full scan results.
struct ARComponentDetailSheet: View {
    let component: Component
    let result: ScanResult
    /// Opens the full results screen; nil hides the button.
    var onOpenResult: ((ScanResult) -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ComponentDetailView(component: component, preferredMetric: .carbon, plugAction: plugAction)
                    .padding()
            }
            .navigationTitle(component.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onOpenResult {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Full results", systemImage: "list.bullet.rectangle") {
                            dismiss()
                            onOpenResult(result)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private var plugAction: (() -> Void)? {
        guard model.flags.plugFeaturesEnabled else { return nil }
        return {
            dismiss()
            model.selectedTab = .plugs
        }
    }
}

#Preview {
    let result = SampleScans.preview()
    ARComponentDetailSheet(component: result.components[0], result: result)
        .environment(AppModel.preview())
}
