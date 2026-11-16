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
            Text(editing == nil ? "New protein batch":"Protein details").font(.title2.bold())
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
            HStack { Spacer();Button("Cancel",role:.cancel) { dismiss() };Button("Save",action:save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:570,height:560)
        .onAppear { if let b=editing { name=b.name;variant=b.variant;batchLabel=b.batchLabel;concentration=b.concentrationMgML.map(editableNumber) ?? "";buffer=b.buffer;notes=b.notes;prepared=b.preparedOn ?? Date();hasDate=b.preparedOn != nil } }
    }
    private func save() {
        do {
            guard !clean(name).isEmpty else { throw LabError("Give the protein a name.") }
            let c=try editedQuantity(concentration,original:editing?.concentrationMgML,name:"concentration",optional:true)
            if let b=editing { b.name=clean(name);b.variant=clean(variant);b.batchLabel=clean(batchLabel);b.concentrationMgML=c;b.buffer=clean(buffer);b.notes=clean(notes);b.preparedOn=hasDate ? prepared:nil;try Inventory.save(context) }
            else { try Inventory.addBatch(ProteinBatch(name:clean(name),variant:clean(variant),batchLabel:clean(batchLabel),preparedOn:hasDate ? prepared:nil,concentration:c,buffer:clean(buffer),notes:clean(notes)),in:context) }
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
                if available.isEmpty { Text("Add a sample in the Samples tab first.") }
                else { ScrollView { VStack(spacing:8) { ForEach(available) { a in Button { choice=a.id } label: { HStack { Text(a.label);Text(a.batch?.name ?? "").foregroundStyle(.secondary);Spacer();Text(volumeLabel(a.remainingUL)) }.padding(6) } } }.padding(2) }.frame(maxHeight:400) }
                HStack { Spacer();Button("Cancel",role:.cancel) { dismiss() } }
            }.padding(24).frame(width:560).frame(maxHeight:600)
        }
    }
}
