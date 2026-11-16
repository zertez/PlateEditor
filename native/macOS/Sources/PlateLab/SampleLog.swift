import Foundation

extension SampleEvent {
    func activityTitle(concentrationUnit: ProteinConcentrationUnit) -> String {
        if let after = valueAfter {
            let concentration = kind == EventKind.concentrationCorrection.rawValue
            let unit = concentration ? concentrationUnit.rawValue : "µL"
            let name = concentration ? "Concentration" : "Volume"
            return "\(name): \(valueBefore.map(number) ?? "Unknown") → \(number(after)) \(unit)"
        }
        switch EventKind(rawValue: kind) {
        case .thawWithMeasurement:
            return "Thawed (+1) · measured with \(volumeLabel(-volumeDeltaUL))"
        case .thawCountDecrease:
            return volumeDeltaUL > 0 ? "Thaw corrected (−1) · restored \(volumeLabel(volumeDeltaUL))" : "Thaw count corrected (−1)"
        case .thaw, .thawCountIncrease: return "Thawed (+1)"
        case .withdrawal: return "Taken out \(volumeLabel(-volumeDeltaUL))"
        case .volumeCorrection:
            if let volume = volumeAfterUL { return "Volume set to \(volumeLabel(volume))" }
            return "Volume adjusted by \(volumeLabel(volumeDeltaUL))"
        default: return kind
        }
    }

    var logDateLabel: String {
        date.map { $0.formatted(date: .abbreviated, time: dateOnly ? .omitted : .shortened) } ?? "Undated"
    }
}

enum SampleLog {
    static func entries(_ events: [SampleEvent], sampleID: UUID? = nil, search: String = "",
                        concentrationUnit: ProteinConcentrationUnit = .milligramsPerMilliliter) -> [SampleEvent] {
        let query = clean(search)
        return events.filter { event in
            guard sampleID == nil || event.aliquot?.id == sampleID else { return false }
            guard !query.isEmpty else { return true }
            let searchable = [event.aliquot?.label ?? "", event.aliquot?.batch?.title ?? "",
                              event.kind, event.activityTitle(concentrationUnit: concentrationUnit),
                              event.notes, event.experiment, event.wells, event.newLocation ?? "", event.logDateLabel]
            return searchable.contains { $0.localizedStandardContains(query) }
        }.sorted { lhs, rhs in
            // Undated imported records remain visible, without inventing a timestamp.
            if lhs.date != rhs.date { return (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast) }
            let leftSample = lhs.aliquot?.id.uuidString ?? ""
            let rightSample = rhs.aliquot?.id.uuidString ?? ""
            if leftSample != rightSample { return leftSample < rightSample }
            if lhs.sequence != rhs.sequence { return lhs.sequence > rhs.sequence }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
