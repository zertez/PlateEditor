import SwiftUI
import SwiftData

struct SampleValueEdit: Identifiable {
    let id = UUID()
    let sample: Aliquot
    let action: SampleEditAction
}

enum SampleEditAction: Equatable {
    case value(SampleValueField), withdrawal
    var field: SampleValueField {
        if case .value(let field) = self { return field }
        return .volume
    }
}

struct EditableSampleValue: View {
    @AppStorage("proteinConcentrationDisplayUnit") private var concentrationUnit: ProteinConcentrationUnit = .milligramsPerMilliliter
    @EnvironmentObject var app: AppState
    let sample: Aliquot
    let field: SampleValueField

    private var displayedUnit: String { field.unit(concentration: concentrationUnit) }

    var body: some View {
        Text(field.value(in: sample).map(number) ?? "—")
            .monospacedDigit().fontWeight(field == .volume ? .medium : .regular)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 26)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: openEditor)
            .accessibilityAction(named: Text("Edit value"), openEditor)
            .accessibilityLabel("\(field.title) for \(sample.label), \(displayedUnit)")
            .accessibilityValue(field.value(in: sample).map(number) ?? "Unknown")
            .help("Double-click to open the editor. Return moves to the reason for change. Escape cancels.")
    }

    private func openEditor() {
        guard !sample.archived else { return }
        app.valueEdit = SampleValueEdit(sample: sample, action: .value(field))
    }
}

// One centered dialog keeps the value and reason together during the slide.
struct SampleValueEditor: View {
    @AppStorage("proteinConcentrationDisplayUnit") private var concentrationUnit: ProteinConcentrationUnit = .milligramsPerMilliliter
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sample: Aliquot
    let action: SampleEditAction
    let close: () -> Void
    @State private var expected: Double?
    @State private var draft: String
    @State private var proposed: Double?
    @State private var reason = ""
    @State private var error: String?
    @State private var step = Step.value
    @State private var movingForward = true
    @FocusState private var focused: Step?

    private enum Step: Hashable { case value, reason }

    init(sample: Aliquot, action: SampleEditAction, close: @escaping () -> Void) {
        self.sample = sample; self.action = action; self.close = close
        let value = action.field.value(in: sample)
        _expected = State(initialValue: value)
        _draft = State(initialValue: action == .withdrawal ? "" : value.map(editableNumber) ?? "")
    }

    private var field: SampleValueField { action.field }
    private var isWithdrawal: Bool { action == .withdrawal }
    private var displayedUnit: String { field.unit(concentration: concentrationUnit) }
    private var changeSummary: String {
        if isWithdrawal, let expected, let proposed {
            return "Taking out \(number(proposed)) µL · \(number(expected - proposed)) µL will remain"
        }
        return "\(field.title): \(expected.map(number) ?? "Unknown") → \(proposed.map(number) ?? "—") \(displayedUnit)"
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(sample.label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Capsule().fill(step == .value ? Color.teal : Color.teal.opacity(0.2))
                    Capsule().fill(step == .reason ? Color.teal : Color.teal.opacity(0.2))
                }.frame(width: 34, height: 4)
                    .accessibilityLabel(step == .value ? "Step 1 of 2" : "Step 2 of 2")
            }
            ZStack(alignment: .topLeading) {
                if step == .value {
                    valuePage.transition(pageTransition)
                } else {
                    reasonPage.transition(pageTransition)
                }
            }
            .frame(height: 116, alignment: .topLeading)
            .clipped()
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                if step == .reason {
                    Button { changeStep(to: .value) } label: { Label("Back", systemImage: "chevron.left") }
                    Button(isWithdrawal ? "Log withdrawal" : "Save change", action: save).buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction).disabled(clean(reason).isEmpty)
                } else {
                    Button(action: advance) { HStack(spacing: 6) { Text("Next"); Image(systemName: "chevron.right") } }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(18).frame(width: 360)
    }

    private var valuePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isWithdrawal ? "How much did you take out?" : "Edit \(field.rawValue)").font(.headline)
            Text(isWithdrawal ? "Enter this withdrawal · \(volumeLabel(expected)) available" : field == .volume ? "Total remaining in this tube (\(displayedUnit))" : "Concentration in this tube (\(displayedUnit))")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField(isWithdrawal ? "Amount taken out" : "New \(field.rawValue)", text: $draft)
                    .textFieldStyle(.plain).font(.title3.weight(.medium)).monospacedDigit()
                    .focused($focused, equals: .value).onSubmit(advance)
                    .accessibilityLabel(isWithdrawal ? "Amount taken out, µL" : "New \(field.rawValue), \(displayedUnit)")
                Text(displayedUnit).font(.callout).foregroundStyle(.secondary)
            }
            .padding(11).background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.teal.opacity(0.3)))
        }
        .onAppear { DispatchQueue.main.async { if step == .value { focused = .value } } }
    }

    private var reasonPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reason for change").font(.headline)
            Text(changeSummary)
                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            TextField("e.g. Took out sample for enzymatic assay", text: $reason)
                .textFieldStyle(.plain).focused($focused, equals: .reason).onSubmit(save)
                .accessibilityLabel("Reason for change")
                .padding(12).background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.teal.opacity(0.3)))
        }
        .onAppear { DispatchQueue.main.async { if step == .reason { focused = .reason } } }
    }

    private func advance() {
        do {
            guard let value = try editedQuantity(draft, original: isWithdrawal ? nil : expected, name: isWithdrawal ? "amount taken out" : field.rawValue) else { return }
            if isWithdrawal {
                guard value > 0 else { throw LabError("Enter an amount greater than zero.") }
                guard let expected else { throw LabError("Record the remaining volume before taking out a sample.") }
                guard value <= expected else { throw LabError("Only \(number(expected)) µL remains in this tube.") }
            } else if value == expected { close(); return }
            proposed = value
            changeStep(to: .reason)
        } catch { self.error = error.localizedDescription }
    }

    private func changeStep(to destination: Step) {
        focused = nil; error = nil
        movingForward = destination == .reason
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.9)) {
            step = destination
        }
    }

    private func save() {
        guard step == .reason, let proposed, !clean(reason).isEmpty else { return }
        do {
            if isWithdrawal {
                try Inventory.withdraw(proposed, from: sample, expectedVolume: expected, reason: reason, in: context)
            } else {
                try Inventory.changeValue(field, for: sample, to: proposed, expected: expected, reason: reason, in: context)
            }
            close()
        } catch { self.error = error.localizedDescription }
    }
}
