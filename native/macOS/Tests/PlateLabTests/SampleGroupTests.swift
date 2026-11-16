import XCTest
import SwiftData
@testable import PlateLab

final class SampleGroupTests: XCTestCase {
    @MainActor func testInlineSectionsKeepEachSampleOnceAndUngroupedSeparate() throws {
        let source = try fixture()
        defer { withExtendedLifetime(source) {} }
        let tubes = source.2
        tubes[0].groupName = "Enzyme B"
        tubes[1].groupName = "Enzyme A"
        let sections = SampleGroups.sections(in: tubes.reversed())
        XCTAssertEqual(sections.map(\.name), ["Enzyme A", "Enzyme B", nil])
        XCTAssertEqual(sections.flatMap(\.samples).map(\.id), [tubes[1].id, tubes[0].id, tubes[2].id])
        XCTAssertEqual(Set(sections.map(\.id)).count, 3)
        XCTAssertNotEqual(SampleGroupSection.identifier(for: "Ungrouped"), SampleGroupSection.identifier(for: nil))
        XCTAssertTrue(SampleGroups.sections(in: []).isEmpty)
        let filtered = SampleGroups.sections(in: [tubes[0]])
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, sections[1].id)
        XCTAssertEqual(tubes.map(\.remainingUL), [100, 100, 100])
        XCTAssertTrue(tubes.allSatisfy { $0.events.isEmpty })
    }

    @MainActor func testGroupingRenamingAndMovingKeepIndependentInventoryAndLogs() throws {
        let (app, batch, tubes) = try fixture()
        let context = app.container.mainContext
        try Inventory.withdraw(3.5, from: tubes[0], expectedVolume: 100, reason: "Assay", in: context)
        try Inventory.record(.thawWithMeasurement, for: tubes[1], in: context)
        let before = SampleBackup(batches: [batch]).batches[0].aliquots
        let name = try SampleGroups.save(name: "  Enzyme A  ", members: Set(tubes.prefix(2).map(\.id)), in: context)
        XCTAssertEqual(name, "Enzyme A")
        XCTAssertEqual(tubes[0].groupName, name)
        XCTAssertEqual(tubes[1].groupName, name)
        XCTAssertNil(tubes[2].groupName)
        XCTAssertEqual(SampleLog.entries(tubes.flatMap(\.events), search: name).count, 2)
        let renamed = try SampleGroups.save(name: "Renamed enzyme", replacing: name, members: [tubes[0].id, tubes[2].id], in: context)
        XCTAssertNil(tubes[1].groupName)
        XCTAssertEqual(tubes[2].groupName, renamed)
        try SampleGroups.move(tubes[1], to: renamed, in: context)
        try SampleGroups.move(tubes[0], to: nil, in: context)
        var after = SampleBackup(batches: [batch]).batches[0].aliquots
        for index in after.indices { after[index].groupName = nil }
        XCTAssertEqual(before, after)
        XCTAssertEqual(tubes[0].remainingUL, 96.5)
        XCTAssertEqual(tubes[1].remainingUL, 98.5)
        XCTAssertEqual(tubes[2].remainingUL, 100)
    }

    @MainActor func testInvalidGroupEditsDoNotChangeMembership() throws {
        let (app, _, tubes) = try fixture()
        let context = app.container.mainContext
        _ = try SampleGroups.save(name: "Enzyme", members: [tubes[0].id], in: context)
        for invalid in ["", "   ", "enzyme"] {
            XCTAssertThrowsError(try SampleGroups.save(name: invalid, members: [tubes[1].id], in: context))
        }
        XCTAssertThrowsError(try SampleGroups.save(name: "New", members: [], in: context))
        XCTAssertThrowsError(try SampleGroups.save(name: "New", members: [UUID()], in: context))
        XCTAssertThrowsError(try SampleGroups.move(tubes[1], to: "Missing", in: context))
        XCTAssertEqual(tubes[0].groupName, "Enzyme")
        XCTAssertNil(tubes[1].groupName)
        XCTAssertEqual(SampleGroups.names(in: tubes), ["Enzyme"])
    }

    @MainActor func testGroupsRoundTripInBackupsAndLegacyBackupsStayUngrouped() throws {
        let (app, batch, tubes) = try fixture()
        _ = try SampleGroups.save(name: "Enzyme", members: [tubes[0].id, tubes[1].id], in: app.container.mainContext)
        let backup = SampleBackup(batches: [batch])
        let decoded = try JSONDecoder().decode(SampleBackup.self, from: backup.data())
        XCTAssertEqual(decoded.version, 6)
        try decoded.validate()
        let restored = try AppState(directory: FileManager.default.temporaryDirectory, memory: true)
        XCTAssertEqual(try decoded.merge(into: restored.container.mainContext), 1)
        XCTAssertEqual(try decoded.merge(into: restored.container.mainContext), 0)
        let copied = try restored.container.mainContext.fetch(FetchDescriptor<Aliquot>())
        XCTAssertEqual(copied.filter { $0.groupName == "Enzyme" }.count, 2)
        XCTAssertEqual(copied.filter { $0.groupName == nil }.count, 1)
        var old = decoded
        old.version = 5
        XCTAssertThrowsError(try old.validate())
        for index in old.batches[0].aliquots.indices { old.batches[0].aliquots[index].groupName = nil }
        let oldData = try old.data()
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("groupName"))
        let legacy = try JSONDecoder().decode(SampleBackup.self, from: oldData)
        try legacy.validate()
        let empty = try AppState(directory: FileManager.default.temporaryDirectory, memory: true)
        XCTAssertEqual(try legacy.merge(into: empty.container.mainContext), 1)
        XCTAssertTrue(try empty.container.mainContext.fetch(FetchDescriptor<Aliquot>()).allSatisfy { $0.groupName == nil })
        XCTAssertThrowsError(try legacy.merge(into: restored.container.mainContext))
        XCTAssertEqual(copied.filter { $0.groupName == "Enzyme" }.count, 2)
    }

    @MainActor func testGroupMembershipSurvivesDatabaseReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var app: AppState? = try AppState(directory: directory)
        let sampleID: UUID
        do {
            let sample = Aliquot(label: "Disk test", volume: 100, concentration: 2, thawCount: 0, state: .frozen, location: "")
            sampleID = sample.id
            try Inventory.addSample(sample, with: ProteinBatch(name: "Protein"), in: app!.container.mainContext)
            _ = try SampleGroups.save(name: "Enzyme", members: [sampleID], in: app!.container.mainContext)
        }
        app = nil
        let reopened = try AppState(directory: directory)
        let sample = try XCTUnwrap(reopened.container.mainContext.fetch(FetchDescriptor<Aliquot>()).first)
        XCTAssertEqual(sample.id, sampleID)
        XCTAssertEqual(sample.groupName, "Enzyme")
        XCTAssertEqual(sample.remainingUL, 100)
        XCTAssertTrue(sample.events.isEmpty)
    }

    @MainActor private func fixture() throws -> (AppState, ProteinBatch, [Aliquot]) {
        let app = try AppState(directory: FileManager.default.temporaryDirectory, memory: true)
        let batch = ProteinBatch(name: "Protein")
        try Inventory.addBatch(batch, in: app.container.mainContext)
        let tubes = try (1...3).map { index in
            let tube = Aliquot(label: "Tube \(index)", volume: 100, concentration: Double(index), thawCount: 0, state: .frozen, location: "")
            try Inventory.addAliquot(tube, to: batch, in: app.container.mainContext)
            return tube
        }
        return (app, batch, tubes)
    }
}
