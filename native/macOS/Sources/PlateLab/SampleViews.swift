import SwiftUI
import SwiftData

struct SampleLibraryView: View {
    @EnvironmentObject var app: AppState
    @Query(sort:\ProteinBatch.createdAt,order:.reverse) private var batches: [ProteinBatch]
    @State private var selected: UUID?
    @State private var search=""
    @State private var addBatch=false
    @State private var addTube=false
    @State private var showArchived=false
    var matching: [Aliquot] {
        batches.flatMap(\.aliquots).filter { a in
            (showArchived || !a.archived) && (search.isEmpty || [a.label,a.batch?.title ?? "",a.location].joined(separator:" ").localizedCaseInsensitiveContains(search))
        }.sorted { $0.createdAt > $1.createdAt }
    }
    var current: Aliquot? { batches.flatMap(\.aliquots).first { $0.id==selected } }
    var body: some View {
        VStack(spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:5) { Text("Protein samples").font(.largeTitle.bold());Text("Every tube, every withdrawal, every thaw.").foregroundStyle(.secondary) }
                Spacer()
                Button { addBatch=true } label: { Label("New protein batch",systemImage:"plus") }
                Button { addTube=true } label: { Label("Add aliquot",systemImage:"testtube.2") }.buttonStyle(.borderedProminent).disabled(batches.isEmpty)
            }.padding(24)
            HStack { TextField("Search tube, protein, batch, or location",text:$search).textFieldStyle(.roundedBorder);Toggle("Show archived",isOn:$showArchived).toggleStyle(.checkbox) }.padding(.horizontal,24).padding(.bottom,16)
            Divider()
            if batches.isEmpty {
                ContentUnavailableView { Label("Start your sample library",systemImage:"testtube.2") } description: { Text("Create a protein batch, then register each aliquot with its remaining volume and known thaw history.") } actions: { Button("New protein batch") { addBatch=true }.buttonStyle(.borderedProminent) }
            } else {
                HSplitView {
                    VStack(alignment:.leading,spacing:0) {
                        if matching.isEmpty {
                            ContentUnavailableView("No aliquots yet",systemImage:"testtube.2",description:Text("Add a tube from one of your \(batches.count) protein batches, or adjust the filter."))
                        } else {
                            List(matching,selection:$selected) { a in
                                VStack(alignment:.leading,spacing:7) {
                                    HStack { Text(a.label).font(.headline);Spacer();Text("\(number(a.remainingUL)) µL").monospacedDigit().fontWeight(.semibold) }
                                    Text(a.batch?.title ?? "Unlinked batch").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    HStack { Label(a.state.rawValue,systemImage:a.state == .frozen ? "snowflake":"drop");Spacer();Text(a.archived ? "Archived":"\(a.thawLabel) thaws") }.font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical,7).tag(a.id)
                            }.listStyle(.inset)
                        }
                        Divider()
                        Text("\(batches.count) batches · \(matching.count) aliquots shown").font(.caption).foregroundStyle(.secondary).padding(12)
                    }.frame(minWidth:275,idealWidth:340,maxWidth:420)
                    if let current { AliquotDetail(aliquot:current).id(current.id).frame(minWidth:420) }
                    else { ContentUnavailableView("Select an aliquot",systemImage:"sidebar.left",description:Text("Inspect quantities, storage, and a dated history. Unknown thaw counts stay unknown.")).frame(minWidth:420,maxWidth:.infinity) }
                }
            }
        }
        .sheet(isPresented:$addBatch) { BatchForm() }
        .sheet(isPresented:$addTube) { AliquotForm(batches:batches,onCreated:{selected=$0}) }
    }
}
struct AliquotDetail: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var app: AppState
    let aliquot: Aliquot
    @State private var action: EventKind?
    @State private var editBatch=false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:6) { Text(aliquot.label).font(.title.bold());Text(aliquot.batch?.title ?? "").foregroundStyle(.secondary) }
                    Spacer()
                    Menu { Button(aliquot.archived ? "Restore aliquot":"Archive aliquot") { aliquot.archived.toggle();do { try Inventory.save(context) } catch { app.error=error.localizedDescription } };Button("Edit protein batch") { editBatch=true } } label: { Image(systemName:"ellipsis.circle").font(.title2) }.menuStyle(.borderlessButton).fixedSize()
                }
                HStack(spacing:12) {
                    Metric(title:"Remaining",value:"\(number(aliquot.remainingUL)) µL")
                    Metric(title:"Thaws",value:aliquot.thawLabel)
                    Metric(title:"State",value:aliquot.state.rawValue)
                }
                Grid(alignment:.leading,horizontalSpacing:20,verticalSpacing:10) {
                    info("Concentration",aliquot.concentrationMgML.map { "\(number($0)) mg/mL" } ?? "Not recorded")
                    info("Protein remaining",aliquot.massUG.map { "\(number($0)) µg" } ?? "Unknown concentration")
                    info("Location",aliquot.location.isEmpty ? "Not recorded":aliquot.location)
                    info("Buffer",aliquot.batch?.buffer.isEmpty == false ? aliquot.batch!.buffer:"Not recorded")
                    if let date=aliquot.batch?.preparedOn { info("Prepared",date.formatted(date:.abbreviated,time:.omitted)) }
                }.font(.subheadline).textSelection(.enabled)
                if !aliquot.notes.isEmpty { Text(aliquot.notes).textSelection(.enabled) }
                if let note=aliquot.batch?.notes,!note.isEmpty { Text(note).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                if aliquot.startingThawCount==nil { Text("Earlier thaw history is unknown. The count includes only events recorded after registration.").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Record withdrawal") { action = .withdrawal }.buttonStyle(.borderedProminent).disabled(aliquot.remainingUL<=0)
                    Button("Mark thawed") { action = .thaw }.disabled(aliquot.state != .frozen)
                    Button("Mark frozen") { action = .freeze }.disabled(aliquot.state == .frozen)
                }.disabled(aliquot.archived)
                HStack { Button("Move storage") { action = .moved };Button("Correct volume") { action = .volumeCorrection } }.disabled(aliquot.archived)
                Divider()
                Text("History").font(.title3.bold())
                ForEach(aliquot.orderedEvents.reversed()) { event in
                    VStack(alignment:.leading,spacing:5) {
                        HStack { Text(event.kind).fontWeight(.semibold);Spacer();Text(event.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                        if event.volumeDeltaUL != 0 { Text("\(event.volumeDeltaUL>0 ? "+":"")\(number(event.volumeDeltaUL)) µL").monospacedDigit() }
                        if let location=event.newLocation { Text(location) }
                        if !event.experiment.isEmpty { Label(event.experiment,systemImage:"square.grid.3x3").font(.subheadline) }
                        if !event.wells.isEmpty { Text("Wells: \(event.wells)").font(.caption) }
                        if !event.notes.isEmpty { Text(event.notes).font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:8))
                }
                VStack(alignment:.leading,spacing:5) {
                    Text("Registered").fontWeight(.semibold)
                    Text("\(number(aliquot.startingVolumeUL)) µL · \(aliquot.initialState) · Starting thaws: \(aliquot.startingThawCount.map(String.init) ?? "unknown")")
                    Text(aliquot.createdAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline)
            }.padding(24)
        }
        .sheet(item:Binding(get:{action.map(EventSelection.init)},set:{action=$0?.kind})) { selection in EventForm(aliquot:aliquot,kind:selection.kind) }
        .sheet(isPresented:$editBatch) { if let batch=aliquot.batch { BatchForm(editing:batch) } }
    }
    func info(_ title: String,_ value: String) -> some View { GridRow { Text(title).foregroundStyle(.secondary);Text(value).frame(maxWidth:.infinity,alignment:.leading) } }
}
struct EventSelection: Identifiable { let kind: EventKind;var id: String {kind.rawValue} }
struct Metric: View {
    let title: String;let value: String
    var body: some View { VStack(alignment:.leading,spacing:6) { Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.headline).monospacedDigit().minimumScaleFactor(0.8) }.frame(maxWidth:.infinity,alignment:.leading).padding(13).background(Color.accentColor.opacity(0.07),in:RoundedRectangle(cornerRadius:10)) }
}
