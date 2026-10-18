import SwiftUI
import GreenCore
import GreenCoreFakes

/// A history entry's results, resolved against the live scan list, with Delete in a toolbar menu. Deleting asks
/// first, then goes back to the list; a scan deleted from another tab leaves a "Scan deleted" note instead.
struct HistoryScanDetail: View {
    let scanID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    /// The scan deleted here, kept on screen while the pop animates so it does not flash "Scan deleted".
    @State private var deleted: ScanResult?

    var body: some View {
        if let scan = model.scans.first(where: { $0.id == scanID }) ?? deleted {
            ScanResultView(result: scan)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Delete scan", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                                .accessibilityIdentifier("history.deleteScan")
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                        .accessibilityIdentifier("history.scanMenu")
                        // On the menu so the dialog points at it.
                        .confirmationDialog("Delete this scan?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                            Button("Delete scan", role: .destructive) { delete(scan) }
                                .accessibilityIdentifier("history.confirmDelete")
                        } message: {
                            Text("It is removed from your history and the leaderboard, with its photo. This can't be undone.")
                        }
                    }
                }
        } else {
            ContentUnavailableView("Scan deleted", systemImage: "trash",
                                   description: Text("This scan is no longer in your history."))
        }
    }

    private func delete(_ scan: ScanResult) {
        deleted = scan
        dismiss()
        withAnimation { model.deleteScan(id: scan.id) }
    }
}

#Preview {
    let model = AppModel.preview()
    let scan = SampleScans.preview()
    model.save(scan)
    return NavigationStack { HistoryScanDetail(scanID: scan.id) }.environment(model)
}
