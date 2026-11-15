import Foundation
import SwiftData

enum StorageState: String, Codable, CaseIterable, Identifiable {
    case unknown = "Unknown", frozen = "Frozen", thawed = "Thawed"
    var id: String { rawValue }
}
enum EventKind: String, Codable, CaseIterable {
    case withdrawal = "Withdrawal", freeze = "Frozen", thaw = "Thawed"
    case volumeCorrection = "Volume correction", moved = "Moved"
}
struct LabError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...4))) }
func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
func quantity(_ text: String, name: String, optional: Bool = false) throws -> Double? {
    if clean(text).isEmpty && optional { return nil }
    guard let value = Double(clean(text)), value.isFinite, value >= 0 else {
        throw LabError("Enter a non-negative number for \(name). Use a decimal point, for example 12.5.")
    }
    return value
}

@Model final class ProteinBatch {
    @Attribute(.unique) var id: UUID
    var name: String
    var variant: String
    var batchLabel: String
    var preparedOn: Date?
    var concentrationMgML: Double?
    var buffer: String
    var notes: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Aliquot.batch) var aliquots: [Aliquot] = []
    init(id: UUID = UUID(), name: String, variant: String = "", batchLabel: String = "", preparedOn: Date? = nil, concentration: Double? = nil, buffer: String = "", notes: String = "", createdAt: Date = Date()) {
        self.id=id; self.name=name; self.variant=variant; self.batchLabel=batchLabel
        self.preparedOn=preparedOn; self.concentrationMgML=concentration; self.buffer=buffer; self.notes=notes; self.createdAt=createdAt
    }
    var title: String { [name, variant, batchLabel].filter { !$0.isEmpty }.joined(separator: " · ") }
}
@Model final class Aliquot {
    @Attribute(.unique) var id: UUID
    var label: String
    var startingVolumeUL: Double
    var concentrationMgML: Double?
    var startingThawCount: Int?
    var initialState: String
    var initialLocation: String
    var notes: String
    var archived: Bool
    var createdAt: Date
    var batch: ProteinBatch?
    @Relationship(deleteRule: .cascade, inverse: \SampleEvent.aliquot) var events: [SampleEvent] = []
    init(id: UUID = UUID(), label: String, volume: Double, concentration: Double?, thawCount: Int?, state: StorageState, location: String, notes: String = "", createdAt: Date = Date()) {
        self.id=id; self.label=label; self.startingVolumeUL=volume; self.concentrationMgML=concentration
        self.startingThawCount=thawCount; self.initialState=state.rawValue; self.initialLocation=location
        self.notes=notes; self.archived=false; self.createdAt=createdAt
    }
    var orderedEvents: [SampleEvent] { events.sorted { $0.sequence < $1.sequence } }
    var remainingUL: Double { max(0, orderedEvents.reduce(startingVolumeUL) { $0 + $1.volumeDeltaUL }) }
    var recordedThaws: Int { events.filter { $0.kind == EventKind.thaw.rawValue }.count }
    var thawLabel: String { startingThawCount.map { String($0 + recordedThaws) } ?? "Unknown + \(recordedThaws) recorded" }
    var state: StorageState { StorageState(rawValue: orderedEvents.last(where: { $0.newState != nil })?.newState ?? initialState) ?? .unknown }
    var location: String { orderedEvents.last(where: { $0.newLocation != nil })?.newLocation ?? initialLocation }
    var massUG: Double? { concentrationMgML.map { $0 * remainingUL } }
}
@Model final class SampleEvent {
    @Attribute(.unique) var id: UUID
    var sequence: Int
    var date: Date
    var kind: String
    var volumeDeltaUL: Double
    var newState: String?
    var newLocation: String?
    var notes: String
    var experiment: String
    var plateID: String?
    var wells: String
    var aliquot: Aliquot?
    init(id: UUID = UUID(), sequence: Int, date: Date = Date(), kind: EventKind, delta: Double = 0, state: StorageState? = nil, location: String? = nil, notes: String = "", experiment: String = "", plateID: String? = nil, wells: String = "") {
        self.id=id; self.sequence=sequence; self.date=date; self.kind=kind.rawValue; self.volumeDeltaUL=delta
        self.newState=state?.rawValue; self.newLocation=location; self.notes=notes; self.experiment=experiment; self.plateID=plateID; self.wells=wells
    }
}

@MainActor enum Inventory {
    static func addBatch(_ batch: ProteinBatch, in context: ModelContext) throws {
        guard !clean(batch.name).isEmpty else { throw LabError("Give the protein a name.") }
        if let c=batch.concentrationMgML, !c.isFinite || c < 0 { throw LabError("Invalid concentration.") }
        context.insert(batch)
        try save(context)
    }
    static func addAliquot(_ aliquot: Aliquot, to batch: ProteinBatch, in context: ModelContext) throws {
        guard !clean(aliquot.label).isEmpty, aliquot.startingVolumeUL.isFinite, aliquot.startingVolumeUL >= 0 else { throw LabError("Enter a tube ID and a non-negative starting volume.") }
        guard aliquot.startingThawCount == nil || aliquot.startingThawCount! >= 0 else { throw LabError("Thaw count cannot be negative.") }
        if let c=aliquot.concentrationMgML, !c.isFinite || c < 0 { throw LabError("Invalid concentration.") }
        let all=try context.fetch(FetchDescriptor<Aliquot>())
        guard !all.contains(where: { $0.label.caseInsensitiveCompare(clean(aliquot.label)) == .orderedSame }) else { throw LabError("That tube ID already exists. Use a unique ID for each aliquot.") }
        aliquot.label=clean(aliquot.label); context.insert(aliquot); aliquot.batch=batch
        try save(context)
    }
    static func record(_ kind: EventKind, for aliquot: Aliquot, amount: Double? = nil, location: String = "", notes: String = "", experiment: String = "", plateID: String? = nil, wells: String = "", in context: ModelContext) throws {
        guard !aliquot.archived else { throw LabError("Restore this aliquot before recording an event.") }
        var delta=0.0; var state: StorageState?; var newLocation: String?
        switch kind {
        case .withdrawal:
            guard let amount, amount.isFinite, amount > 0 else { throw LabError("Enter the volume actually transferred in µL.") }
            guard amount <= aliquot.remainingUL else { throw LabError("Only \(number(aliquot.remainingUL)) µL remains in this aliquot.") }
            delta = -amount
        case .volumeCorrection:
            guard let amount, amount.isFinite, amount >= 0, !clean(notes).isEmpty else { throw LabError("Enter the corrected remaining volume and a reason for the correction.") }
            delta=amount-aliquot.remainingUL
        case .thaw:
            guard aliquot.state == .frozen else { throw LabError("Only a currently frozen aliquot can be marked thawed. Its starting state may be unknown.") }
            state = .thawed
        case .freeze:
            guard aliquot.state != .frozen else { throw LabError("This aliquot is already marked frozen.") }
            state = .frozen
        case .moved:
            guard !clean(location).isEmpty else { throw LabError("Enter the new storage location.") }
            newLocation=clean(location)
        }
        let event=SampleEvent(sequence:(aliquot.events.map(\.sequence).max() ?? 0)+1,kind:kind,delta:delta,state:state,location:newLocation,notes:clean(notes),experiment:clean(experiment),plateID:plateID,wells:wells)
        context.insert(event); event.aliquot=aliquot
        try save(context)
    }
    static func save(_ context: ModelContext) throws {
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
