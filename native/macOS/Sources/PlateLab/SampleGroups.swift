import Foundation
import SwiftData

struct SampleGroupSection: Identifiable {
    let name: String?
    let samples: [Aliquot]
    var id: String { Self.identifier(for: name) }
    static func identifier(for name: String?) -> String { name.map { "group:\($0)" } ?? "ungrouped" }
}

enum SampleGroups {
    static func names(in samples: [Aliquot]) -> [String] {
        Array(Set(samples.compactMap(\.groupName))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func sections(in samples: [Aliquot]) -> [SampleGroupSection] {
        let grouped = Dictionary(grouping: samples, by: \.groupName)
        let names: [String?] = names(in: samples).map(Optional.some) + (grouped[nil] == nil ? [] : [nil])
        return names.map { name in
            SampleGroupSection(name: name, samples: (grouped[name] ?? []).sorted {
                $0.label.localizedStandardCompare($1.label) == .orderedAscending
            })
        }
    }

    @MainActor static func save(name: String, replacing original: String? = nil, members: Set<UUID>, in context: ModelContext) throws -> String {
        let name = clean(name)
        guard !name.isEmpty else { throw LabError("Give the group a name.") }
        guard !members.isEmpty else { throw LabError("Choose at least one sample for this group.") }
        let samples = try context.fetch(FetchDescriptor<Aliquot>())
        guard members.isSubset(of: Set(samples.map(\.id))) else { throw LabError("A selected sample is no longer available. Reopen the group and try again.") }
        guard !names(in: samples).contains(where: { $0 != original && $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw LabError("A group with this name already exists. Choose it and use Edit group to add samples.")
        }
        for sample in samples {
            if members.contains(sample.id) { sample.groupName = name }
            else if let original, sample.groupName == original { sample.groupName = nil }
        }
        try Inventory.save(context)
        return name
    }

    @MainActor static func move(_ sample: Aliquot, to name: String?, in context: ModelContext) throws {
        if let name {
            let samples = try context.fetch(FetchDescriptor<Aliquot>())
            guard names(in: samples).contains(name) else { throw LabError("This group no longer exists. Create it again or choose another group.") }
        }
        sample.groupName = name
        try Inventory.save(context)
    }
}
