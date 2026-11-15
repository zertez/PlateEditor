import SwiftUI
import SwiftData

struct BatchForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var editing: ProteinBatch?
    @State private var name="";@State private var variant="";@State private var batchLabel=""
    @State private var concentration="";@State private var buffer="";@State private var notes=""
    @State private var prepared=Date();@State private var hasDate=false;@State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text(editing == nil ? "New protein batch":"Edit protein batch").font(.title2.bold())
            Form {
                TextField("Protein name",text:$name)
                TextField("Variant / construct",text:$variant,prompt:Text("e.g. Cut CSE"))
                TextField("Batch ID",text:$batchLabel)
                TextField("Concentration (mg/mL, optional)",text:$concentration)
                TextField("Buffer",text:$buffer)
                Toggle("Record preparation date",isOn:$hasDate)
                if hasDate { DatePicker("Prepared on",selection:$prepared,displayedComponents:.date) }
                TextField("Notes",text:$notes,axis:.vertical).lineLimit(3...5)
            }.formStyle(.grouped)
            if editing != nil { Text("Existing aliquots keep the concentrations recorded when they were registered.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack { Spacer();Button("Cancel",role:.cancel) { dismiss() };Button("Save batch",action:save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:570,height:560)
        .onAppear { if let b=editing { name=b.name;variant=b.variant;batchLabel=b.batchLabel;concentration=b.concentrationMgML.map { String($0) } ?? "";buffer=b.buffer;notes=b.notes;prepared=b.preparedOn ?? Date();hasDate=b.preparedOn != nil } }
    }
    private func save() {
        do {
            guard !clean(name).isEmpty else { throw LabError("Give the protein a name.") }
            let c=try quantity(concentration,name:"concentration",optional:true)
            if let b=editing { b.name=clean(name);b.variant=clean(variant);b.batchLabel=clean(batchLabel);b.concentrationMgML=c;b.buffer=clean(buffer);b.notes=clean(notes);b.preparedOn=hasDate ? prepared:nil;try Inventory.save(context) }
            else { try Inventory.addBatch(ProteinBatch(name:clean(name),variant:clean(variant),batchLabel:clean(batchLabel),preparedOn:hasDate ? prepared:nil,concentration:c,buffer:clean(buffer),notes:clean(notes)),in:context) }
            dismiss()
        } catch { self.error=error.localizedDescription }
    }
}
struct AliquotForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let batches: [ProteinBatch]
    var onCreated: (UUID)->Void
    @State private var batchID: UUID?
    @State private var label="";@State private var volume="";@State private var concentration=""
    @State private var thawCount="";@State private var state=StorageState.unknown
    @State private var location="";@State private var notes="";@State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Register an aliquot").font(.title2.bold())
            Text("Register an existing tube. This does not withdraw volume from another tube.").foregroundStyle(.secondary).font(.callout)
            Form {
                Picker("Protein batch",selection:$batchID) { Text("Choose a batch").tag(nil as UUID?);ForEach(batches) { Text($0.title).tag(Optional($0.id)) } }
                TextField("Unique tube ID",text:$label,prompt:Text("e.g. CSE-01-A"))
                TextField("Volume now remaining (µL)",text:$volume,prompt:Text("Leave blank if unknown"))
                TextField("This tube’s concentration (mg/mL)",text:$concentration,prompt:Text("Leave blank if unknown"))
                Picker("Current state",selection:$state) { ForEach(StorageState.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Previous thaw count",text:$thawCount,prompt:Text("Leave blank if unknown; 0 means known zero"))
                TextField("Storage location",text:$location,prompt:Text("Freezer · rack · box · position"))
                TextField("Notes",text:$notes,axis:.vertical).lineLimit(2...3)
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack { Spacer();Button("Cancel",role:.cancel) { dismiss() };Button("Add aliquot",action:save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:610,height:650)
        .onAppear { batchID=batches.first?.id;concentration=batches.first?.concentrationMgML.map { String($0) } ?? "" }
        .onChange(of:batchID) { _,new in concentration=batches.first(where:{$0.id==new})?.concentrationMgML.map { String($0) } ?? "" }
    }
    private func save() {
        do {
            guard let batch=batches.first(where:{$0.id==batchID}) else { throw LabError("Choose a protein batch.") }
            let v=try quantity(volume,name:"volume",optional:true),c=try quantity(concentration,name:"concentration",optional:true)
            let count: Int?
            if clean(thawCount).isEmpty { count=nil } else { guard let n=Int(clean(thawCount)),n>=0 else { throw LabError("Thaw count must be a whole number, or blank if unknown.") };count=n }
            let a=Aliquot(label:label,volume:v,concentration:c,thawCount:count,state:state,location:clean(location),notes:clean(notes))
            try Inventory.addAliquot(a,to:batch,in:context);onCreated(a.id);dismiss()
        } catch { self.error=error.localizedDescription }
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
    @State private var amount="";@State private var location="";@State private var notes="";@State private var experiment="";@State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text(kind == .withdrawal ? "Record completed withdrawal":kind.rawValue).font(.title2.bold())
            Text("\(aliquot.label) · \(volumeLabel(aliquot.remainingUL)) remaining").foregroundStyle(.secondary)
            Form {
                if kind == .withdrawal { TextField("Total volume actually transferred (µL)",text:$amount);TextField("Experiment / plate",text:$experiment) }
                if kind == .volumeCorrection { TextField("Correct remaining volume (µL)",text:$amount) }
                if kind == .moved { TextField("New location",text:$location) }
                if kind == .thaw { Text("Records one thaw from the frozen state. Earlier unknown thaw history remains unknown.") }
                if kind == .freeze { Text("Marks the tube frozen. Refreezing does not add another thaw to the count.") }
                if !wellNames.isEmpty { LabeledContent("Linked wells",value:wellNames.joined(separator:", ")) }
                TextField(kind == .volumeCorrection ? "Reason for correction (required)":"Notes (optional)",text:$notes,axis:.vertical).lineLimit(2...4)
            }.formStyle(.grouped)
            if kind == .withdrawal { Text("This records a completed transfer and reduces the remaining volume. Planning or editing a plate does not deduct samples.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Spacer();Button("Cancel",role:.cancel) { dismiss() };Button("Record event",action:save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:590).fixedSize(horizontal:false,vertical:true)
        .onAppear { experiment=plateTitle;location=aliquot.location }
    }
    private func save() {
        do {
            let value=(kind == .withdrawal || kind == .volumeCorrection) ? try quantity(amount,name:"volume"):nil
            try Inventory.record(kind,for:aliquot,amount:value,location:location,notes:notes,experiment:experiment,plateID:plateID,wells:wellNames.joined(separator:", "),in:context)
            dismiss()
        } catch { self.error=error.localizedDescription }
    }
}
struct TransferPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    @Query private var aliquots: [Aliquot]
    @State private var choice: UUID?
    let plateID: String?
    let plateTitle: String
    let wells: [String]
    var available: [Aliquot] { aliquots.filter { !$0.archived && ($0.remainingUL ?? 0)>0 }.sorted { $0.label < $1.label } }
    var body: some View {
        if let a=available.first(where:{$0.id==choice}) { EventForm(aliquot:a,kind:.withdrawal,plateID:plateID,plateTitle:plateTitle,wellNames:wells) }
        else {
            VStack(alignment:.leading,spacing:20) {
                Text("Choose the source aliquot").font(.title2.bold())
                Text(plateTitle).foregroundStyle(.secondary)
                if available.isEmpty { Text("Register a protein batch and aliquot in Samples first.") }
                else { ScrollView { VStack(spacing:8) { ForEach(available) { a in Button { choice=a.id } label: { HStack { Text(a.label);Text(a.batch?.name ?? "").foregroundStyle(.secondary);Spacer();Text(volumeLabel(a.remainingUL)) }.padding(6) } } }.padding(2) }.frame(maxHeight:400) }
                HStack { Spacer();Button("Cancel",role:.cancel) { dismiss() } }
            }.padding(24).frame(width:560).frame(maxHeight:600)
        }
    }
}
