import SwiftUI
import SwiftData

struct SampleLibraryView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) private var context
    @Query private var aliquots: [Aliquot]
    @State private var selected: UUID?
    @State private var search = ""
    @State private var showArchived = false
    @State private var sheet: SampleSheet?
    @State private var thawSample: Aliquot?
    @AppStorage("proteinMassDisplayUnit") private var massUnit: ProteinMassUnit = .automatic
    @AppStorage("proteinConcentrationDisplayUnit") private var concentrationUnit: ProteinConcentrationUnit = .milligramsPerMilliliter

    private var matching: [Aliquot] {
        aliquots.filter {
            (showArchived || !$0.archived) &&
            (search.isEmpty || [$0.label, $0.batch?.title ?? "", $0.location]
                .joined(separator: " ").localizedCaseInsensitiveContains(search))
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Text("Protein samples").font(.title2.weight(.semibold))
                    Text("\(matching.count)").foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a sample", text: $search).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                    .frame(width: 200)
                    Button { sheet = .add } label: { Label("Add sample", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Menu {
                        Toggle("Show archived samples", isOn: $showArchived)
                        Divider()
                        Button("Export samples…", action: app.exportCSV)
                        Button("Save backup…", action: app.exportSamples)
                        Button("Import backup…", action: app.importSamples)
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().help("Library options")
                }
                HStack(spacing: 24) {
                    HStack(spacing: 6) {
                        Text("Concentration").font(.callout).foregroundStyle(.secondary)
                        Picker("Concentration units", selection: $concentrationUnit) {
                            ForEach(ProteinConcentrationUnit.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 158).controlSize(.small)
                            .help("1 mg/mL = 1 µg/µL. The number stays the same; your preferred unit label is remembered.")
                    }
                    HStack(spacing: 6) {
                        Text("Protein left").font(.callout).foregroundStyle(.secondary)
                        Picker("Protein amount units", selection: $massUnit) {
                            ForEach(ProteinMassUnit.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 132).controlSize(.small)
                            .help("Choose µg or mg for every sample, or Auto. 1 mg = 1,000 µg.")
                    }
                    Spacer()
                }
            }.padding(.horizontal, 22).padding(.vertical, 18)
            Divider()
            if aliquots.isEmpty {
                ContentUnavailableView {
                    Label("Your protein samples", systemImage: "testtube.2")
                } description: {
                    Text("Add a sample to track its volume and thaws.")
                } actions: {
                    Button("Add sample") { sheet = .add }.buttonStyle(.borderedProminent)
                }
            } else if matching.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                Table(matching, selection: $selected) {
                    TableColumn("Sample") { a in
                        Button { sheet = .details(a) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.label).fontWeight(.semibold)
                                if let form = a.batch?.variant, !form.isEmpty {
                                    Text(form).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).help("View \(a.label) details and history")
                    }.width(min: 120, ideal: 155, max: 270)
                    TableColumn("Left (µL)") { a in
                        EditableSampleValue(sample: a, field: .volume)
                    }.width(min: 85, ideal: 95, max: 130)
                    TableColumn("Taken out today (µL)") { a in
                        TimelineView(.periodic(from: .now, by: 60)) { clock in
                            Button { openWithdrawal(a) } label: {
                                HStack(spacing: 8) {
                                    Text(number(a.takenOutUL(on: clock.date))).monospacedDigit()
                                    Image(systemName: "plus.circle").font(.callout)
                                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 26)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(.tint)
                                .disabled(a.archived || (a.remainingUL ?? 0) <= 0)
                                .accessibilityLabel("Taken out today for \(a.label). Log a withdrawal")
                                .accessibilityValue(volumeLabel(a.takenOutUL(on: clock.date)))
                                .help("Withdrawals logged today, such as assays. Excludes concentration measurements. Click to enter the amount removed in another withdrawal.")
                        }
                    }.width(min: 145, ideal: 150, max: 185)
                    TableColumn("Conc. (\(concentrationUnit.rawValue))") { a in
                        EditableSampleValue(sample: a, field: .concentration)
                    }.width(min: 100, ideal: 110, max: 150)
                    TableColumn("Protein left") { a in
                        Text(proteinMassLabel(a.massUG, unit: massUnit)).monospacedDigit()
                            .accessibilityLabel("Protein left for \(a.label)")
                            .accessibilityValue(proteinMassLabel(a.massUG, unit: massUnit))
                            .help(a.massUG == nil
                                  ? "Enter both remaining volume and concentration to calculate the protein amount."
                                  : "Calculated from remaining volume × concentration. Updates automatically when either value changes.")
                    }.width(min: 105, ideal: 115, max: 150)
                    TableColumn("Thaws") { a in
                        ThawCounter(aliquot: a)
                    }.width(min: 120, ideal: 130, max: 180)
                    TableColumn("Location") { a in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.location.isEmpty ? "—" : a.location).lineLimit(1)
                            if a.state != .unknown {
                                Text(a.state.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }.help(a.location)
                    }.width(min: 75, ideal: 110, max: 260)
                    TableColumn("") { a in
                        Menu {
                            Button("Log withdrawal…") { openWithdrawal(a) }
                                .disabled(a.archived || (a.remainingUL ?? 0) <= 0)
                            Button("Details & history…") { sheet = .details(a) }
                            Divider()
                            Button("Mark refrozen") { recordState(a) }
                                .disabled(a.archived || a.state == .frozen)
                            Button("Change location…") { sheet = .event(a, .moved) }.disabled(a.archived)
                            Button("Adjust volume…") { sheet = .event(a, .volumeCorrection) }.disabled(a.archived)
                            Divider()
                            Button(a.archived ? "Restore sample" : "Archive sample") { archive(a) }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().help("More actions for \(a.label)")
                    }.width(30)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let a = matching.first(where: { $0.id == id }) {
                        Button("Log withdrawal…") { openWithdrawal(a) }
                            .disabled(a.archived || (a.remainingUL ?? 0) <= 0)
                        Button("Details & history…") { sheet = .details(a) }
                        Divider()
                        Button("Add thaw…") { thawSample = a }.disabled(a.archived || a.countedThaws == Int.max)
                        Button("Correct thaw count (−1)") { changeCount(a, kind: .thawCountDecrease) }.disabled(a.archived || a.countedThaws == 0)
                        Button("Mark refrozen") { recordState(a) }
                            .disabled(a.archived || a.state == .frozen)
                        Button("Change location…") { sheet = .event(a, .moved) }.disabled(a.archived)
                        Button("Adjust volume…") { sheet = .event(a, .volumeCorrection) }.disabled(a.archived)
                    }
                }
            }
            Divider()
            HStack {
                Text("Taken out today excludes concentration measurements. Thaw + asks whether you used 1.5 µL.")
                Spacer()
                Text("— Not recorded").foregroundStyle(.tertiary)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 11)
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .add: AddSampleForm()
            case .details(let a): SampleDetailsView(aliquot: a)
            case .event(let a, let kind): EventForm(aliquot: a, kind: kind)
            }
        }
        .modifier(ThawConfirmation(sample: $thawSample))
    }

    private func openWithdrawal(_ sample: Aliquot) {
        guard !sample.archived, (sample.remainingUL ?? 0) > 0 else { return }
        app.valueEdit = SampleValueEdit(sample: sample, action: .withdrawal)
    }

    private func recordState(_ a: Aliquot) {
        do { try Inventory.record(.freeze, for: a, in: context) }
        catch { app.error = error.localizedDescription }
    }
    private func changeCount(_ a: Aliquot, kind: EventKind) {
        do { try Inventory.record(kind, for: a, in: context) }
        catch { app.error = error.localizedDescription }
    }
    private func archive(_ a: Aliquot) {
        a.archived.toggle()
        do { try Inventory.save(context) } catch { app.error = error.localizedDescription }
    }
}

private enum SampleSheet: Identifiable {
    case add, details(Aliquot), event(Aliquot, EventKind)
    var id: String {
        switch self {
        case .add: "add"
        case .details(let a): "details-\(a.id)"
        case .event(let a, let kind): "\(a.id)-\(kind.rawValue)"
        }
    }
}

private func compactThawCount(_ a: Aliquot) -> String {
    if a.startingThawCount != nil { return String(a.countedThaws) }
    return a.countedThaws == 0 ? "—" : "? + \(a.countedThaws)"
}

struct CounterButtons: View {
    let value: Int?
    var label: String? = nil
    var sampleName = ""
    var decreaseHelp = "Decrease the starting thaw count by one."
    var increaseHelp = "Increase the starting thaw count by one."
    let decrease: () -> Void
    let increase: () -> Void
    var body: some View {
        HStack(spacing: 7) {
            Button(action: decrease) { Image(systemName: "minus").frame(width: 18, height: 20) }
                .disabled((value ?? 0) <= 0)
                .accessibilityLabel("Decrease thaw count \(sampleName)")
                .help(decreaseHelp)
            if let label { Text(label).monospacedDigit().frame(minWidth: 27).accessibilityLabel("Thaw count: \(label)") }
            Button(action: increase) { Image(systemName: "plus").frame(width: 18, height: 20) }
                .disabled(value == nil || value == Int.max || (value ?? -1) < 0)
                .accessibilityLabel("Increase thaw count \(sampleName)")
                .help(increaseHelp)
        }.buttonStyle(.bordered).controlSize(.small)
            .accessibilityElement(children: .contain)
    }
}

private struct ThawCounter: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var app: AppState
    let aliquot: Aliquot
    @State private var thawSample: Aliquot?
    var body: some View {
        CounterButtons(value: aliquot.countedThaws, label: compactThawCount(aliquot), sampleName: "for \(aliquot.label)",
                       decreaseHelp: aliquot.nextThawCorrectionVolumeUL > 0 ? "Undo the latest thaw and restore its 1.5 µL measurement." : "Correct the thaw count by one. This entry has no measurement volume to restore.",
                       increaseHelp: "Add a thaw, then choose whether you used 1.5 µL to measure concentration.",
                       decrease: { change(.thawCountDecrease) }, increase: { thawSample = aliquot })
            .disabled(aliquot.archived)
            .modifier(ThawConfirmation(sample: $thawSample))
    }
    private func change(_ kind: EventKind) {
        do { try Inventory.record(kind, for: aliquot, in: context) }
        catch { app.error = error.localizedDescription }
    }
}

private struct ThawConfirmation: ViewModifier {
    @Binding var sample: Aliquot?
    @Environment(\.modelContext) private var context
    @EnvironmentObject var app: AppState

    func body(content: Content) -> some View {
        content.alert("Used 1.5 µL to measure concentration?", isPresented: Binding(
            get: { sample != nil }, set: { if !$0 { sample = nil } }), presenting: sample) { sample in
                Button("Yes") { record(sample, measured: true) }
                Button("No") { record(sample, measured: false) }
                Button("Cancel", role: .cancel) { }
            } message: { sample in
                Text("\(sample.label) · Adds one thaw. Yes also subtracts 1.5 µL from the remaining volume.")
            }
    }

    private func record(_ sample: Aliquot, measured: Bool) {
        do {
            try Inventory.record(measured ? .thawWithMeasurement : .thawCountIncrease, for: sample,
                                 notes: measured ? "Used 1.5 µL for concentration measurement." : "No concentration measurement.", in: context)
        } catch { app.error = error.localizedDescription }
    }
}

struct SampleDetailsView: View {
    @AppStorage("proteinMassDisplayUnit") private var massUnit: ProteinMassUnit = .automatic
    @AppStorage("proteinConcentrationDisplayUnit") private var concentrationUnit: ProteinConcentrationUnit = .milligramsPerMilliliter
    @Environment(\.dismiss) private var dismiss
    let aliquot: Aliquot
    @State private var showNotes = false
    @State private var showHistory = true
    @State private var showExtra = false
    @State private var editBatch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(aliquot.label).font(.title2.bold())
                    if let form = aliquot.batch?.variant, !form.isEmpty { Text(form).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 30) {
                        detail("Remaining", volumeLabel(aliquot.remainingUL))
                        detail("Concentration", aliquot.currentConcentrationMgML.map { "\(number($0)) \(concentrationUnit.rawValue)" } ?? "Not recorded")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Thaws").font(.caption).foregroundStyle(.secondary)
                            ThawCounter(aliquot: aliquot)
                            Text("+ asks about measurement").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    DisclosureGroup("History (\(aliquot.events.count))", isExpanded: $showHistory) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(aliquot.orderedEvents.reversed()) { event in
                                HistoryRow(event: event)
                                Divider()
                            }
                            HStack {
                                Text("Starting record").fontWeight(.medium)
                                Spacer()
                                Text(volumeLabel(aliquot.startingVolumeUL)).monospacedDigit()
                            }.padding(.vertical, 12)
                        }.padding(.top, 8)
                    }
                    if !aliquot.notes.isEmpty || aliquot.batch?.notes.isEmpty == false {
                        DisclosureGroup("Notes & import source", isExpanded: $showNotes) {
                            VStack(alignment: .leading, spacing: 12) {
                                if !aliquot.notes.isEmpty { Text(aliquot.notes) }
                                if let notes = aliquot.batch?.notes, !notes.isEmpty, !aliquot.notes.contains(notes) { Text(notes) }
                            }.font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }
                    }
                    DisclosureGroup("More details", isExpanded: $showExtra) {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("State", value: aliquot.state.rawValue)
                            LabeledContent("Location", value: aliquot.location.isEmpty ? "Not recorded" : aliquot.location)
                            if let mass = aliquot.massUG { LabeledContent("Protein remaining", value: proteinMassLabel(mass, unit: massUnit)) }
                            if let buffer = aliquot.batch?.buffer, !buffer.isEmpty { LabeledContent("Buffer", value: buffer) }
                            if let date = aliquot.batch?.preparedOn { LabeledContent("Prepared", value: date.formatted(date: .abbreviated, time: .omitted)) }
                            if aliquot.startingThawCount == nil { Text("Earlier thaw history is unknown.").foregroundStyle(.secondary) }
                            Button("Edit protein details…") { editBatch = true }
                        }.font(.callout).padding(.top, 10)
                    }
                }.padding(24)
            }
        }.frame(width: 650, height: 550)
            .sheet(isPresented: $editBatch) { if let batch = aliquot.batch { BatchForm(editing: batch) } }
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryRow: View {
    @AppStorage("proteinConcentrationDisplayUnit") private var concentrationUnit: ProteinConcentrationUnit = .milligramsPerMilliliter
    let event: SampleEvent
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 7) {
                if event.kind == EventKind.volumeCorrection.rawValue, event.volumeAfterUL == nil {
                    Text("Adjustment: \(number(event.volumeDeltaUL)) µL")
                }
                if let location = event.newLocation { Text(location) }
                if !event.wells.isEmpty { Text("Wells: \(event.wells)") }
                if !event.notes.isEmpty { Text(event.notes) }
                if event.notes.isEmpty && event.wells.isEmpty && event.newLocation == nil { Text("No additional notes") }
            }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.vertical, 8)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.activityTitle(concentrationUnit: concentrationUnit)).fontWeight(.medium)
                    if event.valueAfter != nil || [EventKind.withdrawal.rawValue, EventKind.thawCountIncrease.rawValue].contains(event.kind), !event.notes.isEmpty { Text(event.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    if !event.experiment.isEmpty { Text(event.experiment).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                Text(event.logDateLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 11)
    }
}
