import SwiftUI
import GreenCore

/// Past scans from the SwiftData store, filterable by the search-role tab's text; swipe to delete.
/// Expects to be hosted in a `NavigationStack` (RootView provides one per tab).
struct HistoryTab: View {
    /// Read in `body` so converted numbers refresh when Settings switches units.
    @AppStorage(DisplayUnits.defaultsKey) private var unitSystem: UnitSystem = .imperial
    var searchText: String = ""
    @Environment(AppModel.self) private var model

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filtered: [ScanResult] {
        guard !query.isEmpty else { return model.scans }
        return model.scans.filter { $0.matchesHistorySearch(query) }
    }

    var body: some View {
        let _ = unitSystem
        List {
            ForEach(filtered) { scan in
                NavigationLink(value: HistoryRoute(scanID: scan.id)) {
                    HistoryRow(scan: scan)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        withAnimation { model.deleteScan(id: scan.id) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay { emptyState }
        .navigationTitle(query.isEmpty ? "History" : "Search")
        .navigationDestination(for: HistoryRoute.self) { route in
            if let scan = model.scans.first(where: { $0.id == route.scanID }) {
                ScanResultView(result: scan)
            } else {
                ContentUnavailableView("Scan deleted", systemImage: "trash")
            }
        }
        .settingsToolbarButton()
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.scans.isEmpty {
            ContentUnavailableView {
                Label("No scans yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Scans you save appear here.")
            } actions: {
                Button("Start scanning", systemImage: "viewfinder") { model.selectedTab = .scan }
                    .buttonStyle(.glassProminent)
            }
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }
}

/// Navigation value for a history entry; resolved against the live scan list so deletions are safe.
struct HistoryRoute: Hashable {
    let scanID: UUID
}

extension ScanResult {
    /// Case-insensitive match on the scan title, component names, brands and models.
    func matchesHistorySearch(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || components.contains { component in
                [component.name, component.identifiers.brand, component.identifiers.model, component.category.displayName]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(query) }
            }
    }
}

#Preview {
    NavigationStack { HistoryTab() }.environment(AppModel.preview())
}
