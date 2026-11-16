import Foundation
import SwiftData

let concentrationMeasurementVolumeUL = 1.5

enum StorageState: String, Codable, CaseIterable, Identifiable {
    case unknown = "Unknown", frozen = "Frozen", thawed = "Thawed"
    var id: String { rawValue }
}
enum EventKind: String, Codable, CaseIterable {
    case withdrawal = "Withdrawal", freeze = "Frozen", thaw = "Thawed"
    case volumeCorrection = "Volume correction", moved = "Moved"
    case thawCountIncrease = "Thaw count +1", thawCountDecrease = "Thaw count -1"
    case thawWithMeasurement = "Thaw and concentration measurement"
    case concentrationCorrection = "Concentration change"
}
enum SampleValueField: String {
    case volume, concentration
    var title: String { self == .volume ? "Volume" : "Concentration" }
    var unit: String { self == .volume ? "µL" : "mg/mL" }
    func value(in sample: Aliquot) -> Double? { self == .volume ? sample.remainingUL : sample.currentConcentrationMgML }
}
struct LabError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
// Round presentation only. Persisted measurements and calculations retain their precision.
func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(3))) }
func editableNumber(_ value: Double) -> String {
    value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(3)).grouping(.never))
}
func editedQuantity(_ draft: String, original: Double?, name: String, optional: Bool = false) throws -> Double? {
    // Accepting an untouched rounded field must not replace the original measurement.
    if let original, clean(draft) == editableNumber(original) { return original }
    return try quantity(draft, name: name, optional: optional)
}
enum ProteinMassUnit: String, CaseIterable, Identifiable {
    case automatic = "Auto", micrograms = "µg", milligrams = "mg"
    var id: String { rawValue }
}
func proteinMassLabel(_ micrograms: Double?, unit: ProteinMassUnit = .automatic) -> String {
    guard let micrograms else { return "—" }
    let useMilligrams = unit == .milligrams || (unit == .automatic && micrograms >= 1000)
    return useMilligrams ? "\(number(micrograms / 1000)) mg" : "\(number(micrograms)) µg"
}
func volumeLabel(_ value: Double?) -> String { value.map { "\(number($0)) µL" } ?? "Unknown volume" }
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
    var startingVolumeUL: Double?
    var concentrationMgML: Double?
    var startingThawCount: Int?
    var initialState: String
    var initialLocation: String
    var notes: String
    var archived: Bool
    var createdAt: Date
    var batch: ProteinBatch?
    @Relationship(deleteRule: .cascade, inverse: \SampleEvent.aliquot) var events: [SampleEvent] = []
    init(id: UUID = UUID(), label: String, volume: Double?, concentration: Double?, thawCount: Int?, state: StorageState, location: String, notes: String = "", createdAt: Date = Date()) {
        self.id=id; self.label=label; self.startingVolumeUL=volume; self.concentrationMgML=concentration
        self.startingThawCount=thawCount; self.initialState=state.rawValue; self.initialLocation=location
        self.notes=notes; self.archived=false; self.createdAt=createdAt
    }
    var orderedEvents: [SampleEvent] { events.sorted { $0.sequence < $1.sequence } }
    var remainingUL: Double? {
        orderedEvents.reduce(startingVolumeUL) { balance, event in
            if event.kind == EventKind.volumeCorrection.rawValue, let value = event.valueAfter { return value }
            return event.volumeAfterUL ?? balance.map { max(0, $0 + event.volumeDeltaUL) }
        }
    }
    var currentConcentrationMgML: Double? {
        orderedEvents.last(where: { $0.kind == EventKind.concentrationCorrection.rawValue })?.valueAfter ?? concentrationMgML
    }
    var recordedThaws: Int { events.filter { [EventKind.thaw.rawValue, EventKind.thawCountIncrease.rawValue, EventKind.thawWithMeasurement.rawValue].contains($0.kind) }.count }
    var thawCorrections: Int { events.filter { $0.kind == EventKind.thawCountDecrease.rawValue }.count }
    var countedThaws: Int { (startingThawCount ?? 0) + (recordedThaws - thawCorrections) }
    var thawLabel: String { startingThawCount.map { _ in String(countedThaws) } ?? "Unknown + \(countedThaws) recorded" }
    var nextThawCorrectionVolumeUL: Double {
        var measurements: [Double] = []
        for event in orderedEvents {
            switch EventKind(rawValue: event.kind) {
            case .thaw, .thawCountIncrease: measurements.append(0)
            case .thawWithMeasurement: measurements.append(-event.volumeDeltaUL)
            case .thawCountDecrease: _ = measurements.popLast()
            // A measured balance supersedes earlier deductions; correcting an older count must not inflate it.
            case .volumeCorrection: measurements = measurements.map { _ in 0 }
            default: break
            }
        }
        return measurements.last ?? 0
    }
    var state: StorageState { StorageState(rawValue: orderedEvents.last(where: { $0.newState != nil })?.newState ?? initialState) ?? .unknown }
    var location: String { orderedEvents.last(where: { $0.newLocation != nil })?.newLocation ?? initialLocation }
    var massUG: Double? { guard let concentration = currentConcentrationMgML, let remainingUL else { return nil };return concentration * remainingUL }
}
@Model final class SampleEvent {
    @Attribute(.unique) var id: UUID
    var sequence: Int
    var date: Date?
    var dateOnly: Bool = false
    var kind: String
    var volumeDeltaUL: Double
    var volumeAfterUL: Double?
    var valueBefore: Double?
    var valueAfter: Double?
    var newState: String?
    var newLocation: String?
    var notes: String
    var experiment: String
    var plateID: String?
    var wells: String
    var aliquot: Aliquot?
    init(id: UUID = UUID(), sequence: Int, date: Date? = Date(), dateOnly: Bool = false, kind: EventKind, delta: Double = 0, volumeAfter: Double? = nil, state: StorageState? = nil, location: String? = nil, notes: String = "", experiment: String = "", plateID: String? = nil, wells: String = "", valueBefore: Double? = nil, valueAfter: Double? = nil) {
        self.id=id; self.sequence=sequence; self.date=date; self.kind=kind.rawValue; self.volumeDeltaUL=delta
        self.dateOnly=dateOnly;self.volumeAfterUL=volumeAfter
        self.valueBefore=valueBefore;self.valueAfter=valueAfter
        self.newState=state?.rawValue; self.newLocation=location; self.notes=notes; self.experiment=experiment; self.plateID=plateID; self.wells=wells
    }
}

@MainActor enum Inventory {
    static func addBatch(_ batch: ProteinBatch, in context: ModelContext) throws {
        try validateBatch(batch)
        context.insert(batch)
        try save(context)
    }
    private static func validateBatch(_ batch: ProteinBatch) throws {
        guard !clean(batch.name).isEmpty else { throw LabError("Give the protein a name.") }
        if let c=batch.concentrationMgML, !c.isFinite || c < 0 { throw LabError("Invalid concentration.") }
    }
    private static func validateAliquot(_ aliquot: Aliquot, in context: ModelContext) throws {
        guard !clean(aliquot.label).isEmpty else { throw LabError("Enter a sample name.") }
        if let volume=aliquot.startingVolumeUL, !volume.isFinite || volume<0 { throw LabError("Enter a non-negative volume, or leave it blank if unknown.") }
        guard aliquot.startingThawCount == nil || aliquot.startingThawCount! >= 0 else { throw LabError("Thaw count cannot be negative.") }
        if let c=aliquot.concentrationMgML, !c.isFinite || c < 0 { throw LabError("Invalid concentration.") }
        let all=try context.fetch(FetchDescriptor<Aliquot>())
        guard !all.contains(where: { $0.label.caseInsensitiveCompare(clean(aliquot.label)) == .orderedSame }) else { throw LabError("A sample with this name already exists. Use a different name for each tube.") }
    }
    static func addSample(_ aliquot: Aliquot, with batch: ProteinBatch, in context: ModelContext) throws {
        try validateBatch(batch)
        try validateAliquot(aliquot,in:context)
        aliquot.label=clean(aliquot.label)
        context.insert(batch);context.insert(aliquot);aliquot.batch=batch
        try save(context)
    }
    static func addAliquot(_ aliquot: Aliquot, to batch: ProteinBatch, in context: ModelContext) throws {
        try validateAliquot(aliquot,in:context)
        aliquot.label=clean(aliquot.label); context.insert(aliquot); aliquot.batch=batch
        try save(context)
    }
    static func record(_ kind: EventKind, for aliquot: Aliquot, amount: Double? = nil, location: String = "", notes: String = "", experiment: String = "", plateID: String? = nil, wells: String = "", in context: ModelContext) throws {
        guard !aliquot.archived else { throw LabError("Restore this sample before recording an event.") }
        var delta=0.0; var state: StorageState?; var newLocation: String?;var volumeAfter: Double?
        var valueBefore: Double?;var valueAfter: Double?
        switch kind {
        case .withdrawal:
            guard let amount, amount.isFinite, amount > 0 else { throw LabError("Enter the volume actually transferred in µL.") }
            guard let remaining=aliquot.remainingUL else { throw LabError("The remaining volume is unknown. Record a measured volume before withdrawing.") }
            guard amount <= remaining else { throw LabError("Only \(number(remaining)) µL remains in this aliquot.") }
            delta = -amount
        case .volumeCorrection:
            guard let amount, amount.isFinite, amount >= 0, !clean(notes).isEmpty else { throw LabError("Enter the corrected remaining volume and a reason for the correction.") }
            if let remaining=aliquot.remainingUL { delta=amount-remaining } else { volumeAfter=amount }
            valueBefore=aliquot.remainingUL;valueAfter=amount
        case .concentrationCorrection:
            guard let amount, amount.isFinite, amount >= 0, !clean(notes).isEmpty else { throw LabError("Enter a non-negative concentration and a reason for the change.") }
            valueBefore=aliquot.currentConcentrationMgML;valueAfter=amount
        case .thaw:
            guard aliquot.state == .frozen else { throw LabError("Only a currently frozen aliquot can be marked thawed. Its starting state may be unknown.") }
            guard aliquot.countedThaws < Int.max else { throw LabError("The thaw count is already at its maximum.") }
            state = .thawed
        case .thawCountIncrease:
            guard aliquot.countedThaws < Int.max else { throw LabError("The thaw count is already at its maximum.") }
            state = .thawed
        case .thawWithMeasurement:
            guard aliquot.countedThaws < Int.max else { throw LabError("The thaw count is already at its maximum.") }
            if let remaining = aliquot.remainingUL, remaining < concentrationMeasurementVolumeUL {
                throw LabError("This measurement needs 1.5 µL, but only \(number(remaining)) µL remains. The count and volume were not changed.")
            }
            delta = -concentrationMeasurementVolumeUL
            state = .thawed
        case .thawCountDecrease:
            guard aliquot.countedThaws > 0 else { throw LabError("The thaw count cannot go below zero.") }
            delta = aliquot.nextThawCorrectionVolumeUL
        case .freeze:
            guard aliquot.state != .frozen else { throw LabError("This aliquot is already marked frozen.") }
            state = .frozen
        case .moved:
            guard !clean(location).isEmpty else { throw LabError("Enter the new storage location.") }
            newLocation=clean(location)
        }
        let event=SampleEvent(sequence:(aliquot.events.map(\.sequence).max() ?? 0)+1,kind:kind,delta:delta,volumeAfter:volumeAfter,state:state,location:newLocation,notes:clean(notes),experiment:clean(experiment),plateID:plateID,wells:wells,valueBefore:valueBefore,valueAfter:valueAfter)
        context.insert(event); event.aliquot=aliquot
        try save(context)
    }
    static func changeValue(_ field: SampleValueField, for sample: Aliquot, to value: Double, expected: Double?, reason: String, in context: ModelContext) throws {
        guard !sample.archived else { throw LabError("Restore this sample before editing its values.") }
        guard field.value(in: sample) == expected else { throw LabError("This value changed while you were editing. Cancel and enter it again.") }
        guard value.isFinite, value >= 0 else { throw LabError("Enter a non-negative number.") }
        guard !clean(reason).isEmpty else { throw LabError("Enter a reason for the change.") }
        guard expected != value else { return }
        try record(field == .volume ? .volumeCorrection : .concentrationCorrection, for: sample, amount: value, notes: reason, in: context)
    }
    static func save(_ context: ModelContext) throws {
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
