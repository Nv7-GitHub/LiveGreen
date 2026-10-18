import SwiftUI
import GreenCore
import GreenCoreFakes

/// Detail for a tapped AR label (spec §5.1): the same component detail the Results screen shows (flow,
/// inspector with sources, plug card, "Not mine" / "It's mine"), with a route into the full scan results.
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
                ComponentDetailView(component: live.component(withID: component.id) ?? component, preferredMetric: .carbon,
                                    plugAction: plugAction, ownership: (live, markOwned))
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

    /// The saved copy of the scan, so the sheet follows the user's answer.
    private var live: ScanResult { model.scans.first { $0.id == result.id } ?? result }

    /// "Not mine" / "It's mine": saved with the scan, so the labels, totals and leaderboard follow.
    private func markOwned(_ owned: Bool?) {
        model.save(model.makeScanCoordinator().markingOwned(owned, componentID: component.id, in: live))
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
