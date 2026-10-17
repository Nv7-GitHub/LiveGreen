import SwiftUI
import GreenCore

/// Past scans, filterable by the search-role tab's text.
struct HistoryTab: View {
    var searchText: String = ""
    @Environment(AppModel.self) private var model

    private var filtered: [ScanResult] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.scans }
        return model.scans.filter { scan in
            scan.title.localizedCaseInsensitiveContains(query)
                || scan.components.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { scan in
                NavigationLink(value: scan) {
                    VStack(alignment: .leading) {
                        Text(scan.title).font(.headline)
                        Text("\(scan.components.count) items · \(scan.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { filtered[$0].id }.forEach(model.deleteScan)
            }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(searchText.isEmpty ? "No scans yet" : "No matches",
                                       systemImage: "clock.arrow.circlepath")
            }
        }
        .navigationTitle(searchText.isEmpty ? "History" : "Search")
        .navigationDestination(for: ScanResult.self) { ScanResultView(result: $0) }
        .settingsToolbarButton()
    }
}

#Preview {
    NavigationStack { HistoryTab() }.environment(AppModel.preview())
}
