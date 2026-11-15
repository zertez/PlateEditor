import Foundation
import SwiftData

struct EventRecord: Codable, Equatable {
    var id: UUID; var sequence: Int; var date: Date; var kind: EventKind; var delta: Double
    var state: StorageState?; var location: String?; var notes: String; var experiment: String; var plateID: String?; var wells: String
}
struct AliquotRecord: Codable, Equatable {
    var id: UUID; var label: String; var volume: Double; var concentration: Double?; var thaws: Int?
    var state: StorageState; var location: String; var notes: String; var archived: Bool; var created: Date; var events: [EventRecord]
}
struct BatchRecord: Codable, Equatable {
    var id: UUID; var name: String; var variant: String; var batchLabel: String; var prepared: Date?
    var concentration: Double?; var buffer: String; var notes: String; var created: Date; var aliquots: [AliquotRecord]
}
struct SampleBackup: Codable {
    var format = "platelab-samples"
    var version = 1
    var batches: [BatchRecord]
    @MainActor init(batches: [ProteinBatch]) {
        self.batches=batches.map { b in
            BatchRecord(id:b.id,name:b.name,variant:b.variant,batchLabel:b.batchLabel,prepared:b.preparedOn,concentration:b.concentrationMgML,buffer:b.buffer,notes:b.notes,created:b.createdAt,aliquots:b.aliquots.sorted { $0.id.uuidString < $1.id.uuidString }.map { a in
                AliquotRecord(id:a.id,label:a.label,volume:a.startingVolumeUL,concentration:a.concentrationMgML,thaws:a.startingThawCount,state:StorageState(rawValue:a.initialState) ?? .unknown,location:a.initialLocation,notes:a.notes,archived:a.archived,created:a.createdAt,events:a.orderedEvents.map { e in
                    EventRecord(id:e.id,sequence:e.sequence,date:e.date,kind:EventKind(rawValue:e.kind)!,delta:e.volumeDeltaUL,state:e.newState.flatMap(StorageState.init(rawValue:)),location:e.newLocation,notes:e.notes,experiment:e.experiment,plateID:e.plateID,wells:e.wells)
                })
            })
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    func data() throws -> Data { let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];return try encoder.encode(self) }
    func validate() throws {
        guard format=="platelab-samples",version==1 else { throw LabError("This is not a supported PlateLab sample backup.") }
        var ids=Set<UUID>();var labels=Set<String>()
        func unique(_ id: UUID) throws { guard ids.insert(id).inserted else { throw LabError("The backup contains duplicate record IDs.") } }
        func concentration(_ value: Double?) throws { if let value, !value.isFinite || value < 0 { throw LabError("The backup contains an invalid concentration.") } }
        for b in batches {
            try unique(b.id);try concentration(b.concentration)
            guard !clean(b.name).isEmpty else { throw LabError("A protein name is missing.") }
            for a in b.aliquots {
                try unique(a.id);try concentration(a.concentration)
                guard !clean(a.label).isEmpty, labels.insert(clean(a.label).lowercased()).inserted,a.volume.isFinite,a.volume>=0,a.thaws == nil || a.thaws!>=0 else { throw LabError("An aliquot has an invalid ID, volume, or thaw count.") }
                var remaining=a.volume;var state=a.state;var sequence=0
                for e in a.events {
                    try unique(e.id)
                    guard e.sequence==sequence+1,e.delta.isFinite else { throw LabError("The event history has an invalid sequence or volume.") }
                    sequence=e.sequence
                    switch e.kind {
                    case .withdrawal:
                        guard e.delta<0,e.state==nil,e.location==nil else { throw LabError("Invalid withdrawal history.") }
                    case .volumeCorrection:
                        guard !clean(e.notes).isEmpty,e.state==nil,e.location==nil else { throw LabError("A volume correction needs a reason.") }
                    case .thaw:
                        guard state == .frozen,e.state == .thawed,e.delta==0,e.location==nil else { throw LabError("Invalid thaw transition in the backup.") }
                        state = .thawed
                    case .freeze:
                        guard state != .frozen,e.state == .frozen,e.delta==0,e.location==nil else { throw LabError("Invalid freezing transition in the backup.") }
                        state = .frozen
                    case .moved:
                        guard e.delta==0,e.state==nil, !(e.location.map(clean) ?? "").isEmpty else { throw LabError("Invalid storage movement in the backup.") }
                    }
                    remaining += e.delta
                    guard remaining.isFinite,remaining >= -0.00000001 else { throw LabError("The backup would give an aliquot a negative remaining volume.") }
                }
            }
        }
    }
    @MainActor func merge(into context: ModelContext) throws -> Int {
        try validate()
        let current=SampleBackup(batches:try context.fetch(FetchDescriptor<ProteinBatch>()))
        let existing=Dictionary(uniqueKeysWithValues:current.batches.map { ($0.id,$0) })
        let incoming=try batches.filter { b in
            if let old=existing[b.id] {
                guard old==b else { throw LabError("A different version of ‘\(b.name)’ is already present. This import was not applied; existing history is preserved.") }
                return false
            }
            return true
        }
        var combined=self;combined.batches=current.batches+incoming;try combined.validate()
        for b in incoming {
            let batch=ProteinBatch(id:b.id,name:b.name,variant:b.variant,batchLabel:b.batchLabel,preparedOn:b.prepared,concentration:b.concentration,buffer:b.buffer,notes:b.notes,createdAt:b.created);context.insert(batch)
            for a in b.aliquots {
                let aliquot=Aliquot(id:a.id,label:a.label,volume:a.volume,concentration:a.concentration,thawCount:a.thaws,state:a.state,location:a.location,notes:a.notes,createdAt:a.created)
                aliquot.archived=a.archived;context.insert(aliquot);aliquot.batch=batch
                for e in a.events {
                    let event=SampleEvent(id:e.id,sequence:e.sequence,date:e.date,kind:e.kind,delta:e.delta,state:e.state,location:e.location,notes:e.notes,experiment:e.experiment,plateID:e.plateID,wells:e.wells)
                    context.insert(event);event.aliquot=aliquot
                }
            }
        }
        try Inventory.save(context);return incoming.count
    }
}
