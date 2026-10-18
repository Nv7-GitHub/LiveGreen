import SwiftUI
import GreenCore

/// Settings → Scan feedback: the notes left under scan results, which later scans send to identify as weak
/// hints. Swipe a note to delete it, or clear them all.
struct ScanFeedbackSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsClear = false

    var body: some View {
        Section {
            if model.feedback.notes.isEmpty {
                Text("No notes yet. Use “Something off? Tell us” under a scan's results.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.feedback.notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.note).lineLimit(3)
                        Text(subtitle(note))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .onDelete { offsets in
                    for id in offsets.map({ model.feedback.notes[$0].id }) { try? model.feedback.delete(id: id) }
                }
                Button("Clear all", systemImage: "trash", role: .destructive) { confirmsClear = true }
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("settings.clearFeedback")
                    .confirmationDialog("Clear all scan feedback?", isPresented: $confirmsClear, titleVisibility: .visible) {
                        Button("Clear all", role: .destructive) { try? model.feedback.deleteAll() }
                    } message: {
                        Text("Future scans stop using these notes. Your scans are kept.")
                    }
            }
        } header: {
            Text("Scan feedback")
        } footer: {
            Text("New scans send a few of these notes to the AI as hints about your things, not as rules.")
        }
    }

    /// "Mar 3 · TV, Soundbar": when the note was left and what that scan identified.
    private func subtitle(_ note: ScanFeedback) -> String {
        ([note.date.formatted(date: .abbreviated, time: .omitted)] + [note.identifiedItems.prefix(3).joined(separator: ", ")])
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
