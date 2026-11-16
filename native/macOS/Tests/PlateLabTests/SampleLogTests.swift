import XCTest
import SwiftData
@testable import PlateLab

final class SampleLogTests: XCTestCase {
    @MainActor func testLogIncludesArchivedAndUndatedHistoryAndSortsLatestFirst() throws {
        let app = try AppState(directory: FileManager.default.temporaryDirectory, memory: true)
        let sample = Aliquot(label: "Test tube", volume: 100, concentration: 2, thawCount: 0, state: .frozen, location: "")
        try Inventory.addSample(sample, with: ProteinBatch(name: "Test protein"), in: app.container.mainContext)
        try Inventory.record(.withdrawal, for: sample, amount: 3.5, notes: "Enzymatic assay", in: app.container.mainContext)
        let older = try XCTUnwrap(sample.events.first)
        older.date = Date(timeIntervalSince1970: 100)
        try Inventory.record(.thawWithMeasurement, for: sample, in: app.container.mainContext)
        let latest = try XCTUnwrap(sample.orderedEvents.last)
        latest.date = Date(timeIntervalSince1970: 200)
        try Inventory.record(.thawCountIncrease, for: sample, in: app.container.mainContext)
        let undated = try XCTUnwrap(sample.orderedEvents.last)
        undated.date = nil
        sample.archived = true
        try Inventory.save(app.container.mainContext)
        let fetched = try app.container.mainContext.fetch(FetchDescriptor<SampleEvent>())
        XCTAssertEqual(SampleLog.entries(fetched).map(\.id), [latest.id, older.id, undated.id])
        XCTAssertEqual(SampleLog.entries(fetched, search: "enzymatic").map(\.id), [older.id])
        XCTAssertEqual(SampleLog.entries(fetched, search: "TEST TUBE").count, 3)
        XCTAssertEqual(SampleLog.entries(fetched, sampleID: sample.id).count, 3)
        XCTAssertTrue(SampleLog.entries(fetched, sampleID: UUID()).isEmpty)
        // Browsing and filtering leave the persisted inventory and history untouched.
        XCTAssertEqual(sample.remainingUL, 95)
        XCTAssertEqual(sample.events.count, 3)
    }

    func testImportedDatePrecisionAndEqualDateSequenceArePreserved() {
        let date = Date(timeIntervalSince1970: 100)
        let first = SampleEvent(sequence: 1, date: date, dateOnly: true, kind: .withdrawal, delta: -4)
        let second = SampleEvent(sequence: 2, date: date, dateOnly: true, kind: .freeze)
        let undated = SampleEvent(sequence: 3, date: nil, kind: .thaw)
        XCTAssertEqual(SampleLog.entries([first, undated, second]).map(\.id), [second.id, first.id, undated.id])
        XCTAssertEqual(first.logDateLabel, date.formatted(date: .abbreviated, time: .omitted))
        XCTAssertEqual(undated.logDateLabel, "Undated")
    }

    func testActivityDistinguishesAssayUseMeasurementsAndValueCorrections() {
        let assay = SampleEvent(sequence: 1, kind: .withdrawal, delta: -3.5)
        let measurement = SampleEvent(sequence: 2, kind: .thawWithMeasurement, delta: -1.5)
        let change = SampleEvent(sequence: 3, kind: .concentrationCorrection, valueBefore: 0.76, valueAfter: 0.85)
        XCTAssertEqual(assay.activityTitle(concentrationUnit: .milligramsPerMilliliter), "Taken out \(volumeLabel(3.5))")
        XCTAssertEqual(measurement.activityTitle(concentrationUnit: .milligramsPerMilliliter), "Thawed (+1) · measured with \(volumeLabel(1.5))")
        XCTAssertEqual(change.activityTitle(concentrationUnit: .microgramsPerMicroliter), "Concentration: \(number(0.76)) → \(number(0.85)) µg/µL")
        XCTAssertEqual(change.valueAfter, 0.85)
    }
}
