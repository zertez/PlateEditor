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

    private var matching: [Aliquot] {
        aliquots.filter {
            (showArchived || !$0.archived) &&
            (search.isEmpty || [$0.label, $0.batch?.title ?? "", $0.location]
                .joined(separator: " ").localizedCaseInsensitiveContains(search))
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    }.width(min: 130, ideal: 180, max: 270)
                    TableColumn("Left (µL)") { a in
                        Text(a.remainingUL.map(number) ?? "—").monospacedDigit().fontWeight(.medium)
                            .help(a.remainingUL == nil ? "Volume not recorded" : "Remaining volume in µL")
                    }.width(min: 85, ideal: 105, max: 130)
                    TableColumn("Conc. (mg/mL)") { a in
                        Text(a.concentrationMgML.map(number) ?? "—").monospacedDigit()
                    }.width(min: 105, ideal: 120, max: 150)
                    TableColumn("Thaws") { a in
                        Text(compactThawCount(a)).monospacedDigit().help(a.thawLabel)
                    }.width(min: 55, ideal: 65, max: 80)
                    TableColumn("Location") { a in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.location.isEmpty ? "—" : a.location).lineLimit(1)
                            if a.state != .unknown {
                                Text(a.state.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }.help(a.location)
                    }.width(min: 90, ideal: 150, max: 260)
                    TableColumn("") { a in
                        HStack(spacing: 12) {
                            Button("Use…") { sheet = .event(a, .withdrawal) }
                                .disabled(a.archived || (a.remainingUL ?? 0) <= 0)
                            Menu {
                                Button("Details & history…") { sheet = .details(a) }
                                Divider()
                                Button(a.state == .frozen ? "Mark thawed (+1)" : "Mark frozen") { recordState(a) }
                                    .disabled(a.archived)
                                Button("Change location…") { sheet = .event(a, .moved) }.disabled(a.archived)
                                Button("Adjust volume…") { sheet = .event(a, .volumeCorrection) }.disabled(a.archived)
                                Divider()
                                Button(a.archived ? "Restore sample" : "Archive sample") { archive(a) }
                            } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton).fixedSize().help("More actions for \(a.label)")
                        }
                    }.width(112)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let a = matching.first(where: { $0.id == id }) {
                        Button("Use sample…") { sheet = .event(a, .withdrawal) }
                            .disabled(a.archived || (a.remainingUL ?? 0) <= 0)
                        Button("Details & history…") { sheet = .details(a) }
                        Divider()
                        Button(a.state == .frozen ? "Mark thawed (+1)" : "Mark frozen") { recordState(a) }
                            .disabled(a.archived)
                        Button("Change location…") { sheet = .event(a, .moved) }.disabled(a.archived)
                        Button("Adjust volume…") { sheet = .event(a, .volumeCorrection) }.disabled(a.archived)
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let a = matching.first(where: { $0.id == id }) {
                        sheet = .details(a)
                    }
                }
            }
            Divider()
            HStack {
                Text("Click a sample name for details and history.")
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
    }

    private func recordState(_ a: Aliquot) {
        do { try Inventory.record(a.state == .frozen ? .thaw : .freeze, for: a, in: context) }
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
    if let count = a.startingThawCount { return String(count + a.recordedThaws) }
    return a.recordedThaws == 0 ? "—" : "? + \(a.recordedThaws)"
}

struct SampleDetailsView: View {
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
                        detail("Concentration", aliquot.concentrationMgML.map { "\(number($0)) mg/mL" } ?? "Not recorded")
                        detail("Thaws", aliquot.thawLabel)
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
                            if let mass = aliquot.massUG { LabeledContent("Protein remaining", value: "\(number(mass)) µg") }
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
    let event: SampleEvent
    @State private var expanded = false
    private var title: String {
        if event.kind == EventKind.withdrawal.rawValue { return "Used \(volumeLabel(-event.volumeDeltaUL))" }
        if let volume = event.volumeAfterUL { return "Volume set to \(volumeLabel(volume))" }
        return event.kind
    }
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
                    Text(title).fontWeight(.medium)
                    if !event.experiment.isEmpty { Text(event.experiment).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                Text(event.date.map { $0.formatted(date: .abbreviated, time: event.dateOnly ? .omitted : .shortened) } ?? "Undated")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 11)
    }
}
