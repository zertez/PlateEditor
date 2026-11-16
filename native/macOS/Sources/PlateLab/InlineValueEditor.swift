import SwiftUI
import SwiftData

struct EditableSampleValue: View {
    @Environment(\.modelContext) private var context
    let sample: Aliquot
    let field: SampleValueField
    @State private var expected: Double?
    @State private var pending: Double?
    @State private var reason = ""
    @State private var error: String?
    @State private var showPrompt = false
    @FocusState private var valueFocused: Bool
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        Group {
            if editing {
                TextField(field.title, text: $draft)
                    .textFieldStyle(.roundedBorder).focused($valueFocused)
                    .onAppear { DispatchQueue.main.async { valueFocused = true } }
                    .onSubmit(commitDraft)
                    .onExitCommand { editing = false; valueFocused = false }
                    .onChange(of: valueFocused) { _, focused in
                        if !focused && editing { commitDraft() }
                    }
            } else {
                Text((pending ?? field.value(in: sample)).map(number) ?? "—")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEditing)
                    .accessibilityAction(named: Text("Edit value"), beginEditing)
                    .accessibilityValue((pending ?? field.value(in: sample)).map(number) ?? "Unknown")
            }
        }
            .monospacedDigit().fontWeight(field == .volume ? .medium : .regular)
            .frame(height: 26)
            .accessibilityLabel("\(field.title) for \(sample.label), \(field.unit)")
            .help("Double-click to edit. Press Return, then enter a reason. Escape cancels.")
            .popover(isPresented: $showPrompt, arrowEdge: .bottom) {
                ChangeReasonPopover(
                    summary: pending.map { "\(sample.label) · \(field.title): \(expected.map(number) ?? "Unknown") → \(number($0)) \(field.unit)" },
                    reason: $reason, error: error, cancel: dismissPrompt, save: save)
            }
            .onChange(of: showPrompt) { _, shown in
                if !shown { pending = nil; reason = ""; error = nil }
            }
    }

    private func dismissPrompt() {
        showPrompt = false
        pending = nil; reason = ""; error = nil
    }

    private func beginEditing() {
        guard !sample.archived else { return }
        expected = field.value(in: sample)
        draft = expected.map { String($0) } ?? ""
        editing = true
    }
    private func commitDraft() {
        guard editing else { return }
        editing = false
        valueFocused = false
        propose(draft)
    }
    private func propose(_ draft: String) {
        do {
            guard let value = try quantity(draft, name: field.rawValue) else { return }
            guard value != expected else { return }
            pending = value; error = nil; reason = ""; showPrompt = true
        } catch {
            pending = nil; self.error = error.localizedDescription; showPrompt = true
        }
    }
    private func save() {
        guard let pending, !clean(reason).isEmpty else { return }
        do {
            try Inventory.changeValue(field, for: sample, to: pending, expected: expected, reason: reason, in: context)
            dismissPrompt()
        } catch { self.error = error.localizedDescription }
    }
}


// Keep keyboard focus inside the popover's own window, separate from the table cell.
private struct ChangeReasonPopover: View {
    let summary: String?
    @Binding var reason: String
    let error: String?
    let cancel: () -> Void
    let save: () -> Void
    @FocusState private var reasonFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary == nil ? "Check value" : "Reason for change").font(.headline)
            if let summary {
                Text(summary).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("e.g. Took out sample for enzymatic assay", text: $reason)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Reason for change").focused($reasonFocused)
                    .onSubmit(save)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                if summary != nil {
                    Button("Save change", action: save).buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction).disabled(clean(reason).isEmpty)
                }
            }
        }.padding(16).frame(width: 330)
            .onAppear { DispatchQueue.main.async { reasonFocused = true } }
    }
}
