import SwiftUI
import GreenCore

/// "Something off? Tell us": an optional note on the scan in the user's own words ("the TV is actually a large
/// monitor"). Notes stay with the scan and later scans send a few of them to identify as weak hints
/// (`ScanFeedback.promptSection`), so one correction nudges future scans without relabeling every similar item.
struct ScanFeedbackCard: View {
    let result: ScanResult

    @Environment(AppModel.self) private var model
    @State private var isEditing = false
    @State private var draft = ""
    @State private var confirmation: String?
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    private var notes: [ScanFeedback] { model.feedback.notes(forScan: result.id) }
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing { editor } else { opener }
            if let confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.leaf)
                    .transition(.opacity)
                    .accessibilityIdentifier("feedbackConfirmation")
            }
            if !notes.isEmpty { savedNotes }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private var opener: some View {
        Button {
            withAnimation(.smooth) { isEditing = true }
            isFocused = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "text.bubble")
                    .font(.title3)
                    .foregroundStyle(Theme.leaf)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Something off? Tell us").font(.subheadline.weight(.semibold))
                    Text("Correct an item in your own words. Future scans take it into account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus").foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("feedbackOpen")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Something off? Tell us").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Cancel", systemImage: "xmark") { close() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            TextField("e.g. The TV is actually a large monitor", text: $draft, axis: .vertical)
                .lineLimit(2...5)
                .focused($isFocused)
                .padding(10)
                .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                .accessibilityIdentifier("feedbackField")
            HStack(alignment: .center) {
                Text(saveError ?? "Used as a hint for later scans, not a rule.")
                    .font(.caption)
                    .foregroundStyle(saveError == nil ? Color.secondary : Theme.danger)
                Spacer()
                Button("Send", systemImage: "paperplane.fill") { submit() }
                    .buttonStyle(.glassProminent)
                    .disabled(!canSend)
                    .accessibilityIdentifier("feedbackSubmit")
            }
        }
    }

    private var savedNotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(notes.count == 1 ? "Your note" : "Your notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(notes) { note in
                Label {
                    Text(note.note).font(.footnote)
                } icon: {
                    Image(systemName: "quote.bubble").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func submit() {
        do {
            try model.feedback.add(draft, on: result)
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
            return
        }
        withAnimation(.smooth) {
            confirmation = "Thanks. Future scans will take this into account."
            close()
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.smooth) { confirmation = nil }
        }
    }

    private func close() {
        isFocused = false
        draft = ""
        saveError = nil
        withAnimation(.smooth) { isEditing = false }
    }
}

#Preview {
    ScrollView {
        ScanFeedbackCard(result: ResultSamples.desk).padding()
    }
    .environment(AppModel.preview())
}
