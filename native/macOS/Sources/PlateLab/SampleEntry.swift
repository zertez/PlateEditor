import SwiftUI
import SwiftData

struct SampleInput: View {
    let title: String
    @Binding var text: String
    var placeholder = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            TextField(title, text: $text, prompt: Text(placeholder)).labelsHidden()
                .textFieldStyle(.roundedBorder).controlSize(.large)
                .accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AddSampleForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var form = ""
    @State private var volume = ""
    @State private var concentration = ""
    @State private var thaws = ""
    @State private var location = ""
    @State private var state = StorageState.unknown
    @State private var buffer = ""
    @State private var notes = ""
    @State private var more = false
    @State private var error: String?
    @FocusState private var focusName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add sample").font(.title2.weight(.semibold))
            Text("One sample per tube. Leave unknown values blank.").foregroundStyle(.secondary)
            HStack(spacing: 16) {
                SampleInput(title: "Sample name", text: $name, placeholder: "e.g. α").focused($focusName)
                SampleInput(title: "Form", text: $form, placeholder: "e.g. Cut · no His-tag")
            }
            HStack(spacing: 16) {
                SampleInput(title: "Volume left (µL)", text: $volume)
                SampleInput(title: "Concentration (mg/mL)", text: $concentration)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Thaws so far").font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Unknown", text: $thaws).textFieldStyle(.roundedBorder).controlSize(.large)
                            .accessibilityLabel("Thaws so far")
                        CounterButtons(value: clean(thaws).isEmpty ? 0 : Int(clean(thaws)),
                                       decrease: { changeStartingThaws(-1) }, increase: { changeStartingThaws(1) })
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                SampleInput(title: "Location", text: $location, placeholder: "Freezer / box / position")
            }
            DisclosureGroup("More details", isExpanded: $more) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Currently", selection: $state) {
                        ForEach(StorageState.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    SampleInput(title: "Buffer", text: $buffer)
                    SampleInput(title: "Notes", text: $notes)
                }.padding(.top, 10)
            }.foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add sample", action: save).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(clean(name).isEmpty)
            }
        }.padding(24).frame(width: 560).fixedSize(horizontal: false, vertical: true)
            .onAppear { focusName = true }
    }

    private func save() {
        do {
            let v = try quantity(volume, name: "volume", optional: true)
            let c = try quantity(concentration, name: "concentration", optional: true)
            let count: Int?
            if clean(thaws).isEmpty { count = nil }
            else {
                guard let value = Int(clean(thaws)), value >= 0 else { throw LabError("Enter a whole number of thaws, or leave it blank.") }
                count = value
            }
            let batch = ProteinBatch(name: clean(name), variant: clean(form), concentration: c, buffer: clean(buffer))
            let sample = Aliquot(label: name, volume: v, concentration: c, thawCount: count,
                                state: state, location: clean(location), notes: clean(notes))
            try Inventory.addSample(sample, with: batch, in: context)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func changeStartingThaws(_ delta: Int) {
        let value = clean(thaws).isEmpty ? 0 : Int(clean(thaws))
        guard let value, value >= 0, delta < 0 ? value > 0 : value < Int.max else { return }
        thaws = String(value + delta)
    }
}

struct EventForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let aliquot: Aliquot
    let kind: EventKind
    var plateID: String? = nil
    var plateTitle = ""
    var wellNames: [String] = []
    @State private var amount = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var experiment = ""
    @State private var more = false
    @State private var error: String?
    @FocusState private var focusAmount: Bool

    private var title: String {
        switch kind {
        case .withdrawal: "Use \(aliquot.label)"
        case .volumeCorrection: "Adjust volume · \(aliquot.label)"
        case .moved: "Move \(aliquot.label)"
        case .freeze: "Freeze \(aliquot.label)"
        case .thaw: "Thaw \(aliquot.label)"
        case .thawCountIncrease: "Add a thaw · \(aliquot.label)"
        case .thawCountDecrease: "Correct thaw count · \(aliquot.label)"
        }
    }
    private var remainingAfter: Double? {
        guard let current = aliquot.remainingUL, let used = Double(clean(amount)), used.isFinite, used > 0, used <= current else { return nil }
        return current - used
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.weight(.semibold))
            if kind == .withdrawal || kind == .volumeCorrection {
                Text("\(volumeLabel(aliquot.remainingUL)) currently remaining").foregroundStyle(.secondary)
                SampleInput(title: kind == .withdrawal ? "Volume used (µL)" : "New remaining volume (µL)", text: $amount)
                    .focused($focusAmount)
            }
            if kind == .withdrawal {
                if let after = remainingAfter {
                    Text("\(volumeLabel(after)) will remain").font(.callout).foregroundStyle(.secondary)
                }
                if !plateTitle.isEmpty { Label(plateTitle, systemImage: "square.grid.3x3").font(.callout) }
                if !wellNames.isEmpty { Text("Wells: \(wellNames.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup("Add a note", isExpanded: $more) {
                    VStack(spacing: 12) {
                        SampleInput(title: "Experiment", text: $experiment)
                        SampleInput(title: "Notes", text: $notes)
                    }.padding(.top, 10)
                }.foregroundStyle(.secondary)
            }
            if kind == .volumeCorrection { SampleInput(title: "Reason", text: $notes, placeholder: "e.g. Measured again") }
            if kind == .moved { SampleInput(title: "New location", text: $location) }
            if kind == .thaw { Text("Adds one thaw to this sample’s history.") }
            if kind == .freeze { Text("Marks this sample as frozen.") }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(kind == .withdrawal ? "Record use" : "Save", action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 440).fixedSize(horizontal: false, vertical: true)
            .onAppear {
                experiment = plateTitle; location = aliquot.location
                if kind == .volumeCorrection { amount = aliquot.remainingUL.map { String($0) } ?? "" }
                focusAmount = true
            }
    }
    private func save() {
        do {
            let value = (kind == .withdrawal || kind == .volumeCorrection) ? try quantity(amount, name: "volume") : nil
            try Inventory.record(kind, for: aliquot, amount: value, location: location, notes: notes,
                                 experiment: experiment, plateID: plateID, wells: wellNames.joined(separator: ", "), in: context)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
