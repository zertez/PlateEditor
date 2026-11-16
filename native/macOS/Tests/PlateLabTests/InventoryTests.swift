import XCTest
import SwiftData
@testable import PlateLab

final class InventoryTests: XCTestCase {
    @MainActor func testQuickWithdrawalLogsReasonTimeAndUpdatesBalanceAndMassOnce() throws {
        let (app, batch, sample) = try fixture()
        let before = Date()
        try Inventory.withdraw(12.3456, from: sample, expectedVolume: 100, reason: "  Enzymatic assay  ", in: app.container.mainContext)
        XCTAssertEqual(try XCTUnwrap(sample.remainingUL), 87.6544, accuracy: 0.0000001)
        XCTAssertEqual(try XCTUnwrap(sample.massUG), 175.3088, accuracy: 0.0000001)
        XCTAssertEqual(sample.countedThaws, 0)
        XCTAssertEqual(sample.events.count, 1)
        let event = try XCTUnwrap(sample.events.first)
        XCTAssertEqual(event.kind, EventKind.withdrawal.rawValue)
        XCTAssertEqual(event.notes, "Enzymatic assay")
        XCTAssertEqual(event.volumeDeltaUL, -12.3456)
        XCTAssertTrue(try XCTUnwrap(event.date) >= before)
        XCTAssertFalse(event.dateOnly)
        XCTAssertEqual(sample.takenOutUL(on: try XCTUnwrap(event.date)), 12.3456)
        XCTAssertThrowsError(try Inventory.withdraw(12.3456, from: sample, expectedVolume: 100, reason: "Duplicate save", in: app.container.mainContext))
        XCTAssertEqual(sample.events.count, 1)
        let backup = try JSONDecoder().decode(SampleBackup.self, from: SampleBackup(batches: [batch]).data())
        let restored = try AppState(directory: FileManager.default.temporaryDirectory, memory: true)
        _ = try backup.merge(into: restored.container.mainContext)
        let copy = try XCTUnwrap(restored.container.mainContext.fetch(FetchDescriptor<Aliquot>()).first)
        XCTAssertEqual(copy.remainingUL, sample.remainingUL)
        XCTAssertEqual(copy.takenOutUL(on: try XCTUnwrap(event.date)), 12.3456)
        XCTAssertEqual(copy.events.first?.notes, "Enzymatic assay")
    }

    @MainActor func testQuickWithdrawalRejectsInvalidAmountsReasonsAndUnavailableSamples() throws {
        let (app, _, sample) = try fixture()
        let context = app.container.mainContext
        for amount in [0, -1, 101, .nan, .infinity] {
            XCTAssertThrowsError(try Inventory.withdraw(amount, from: sample, expectedVolume: 100, reason: "Assay", in: context))
        }
        XCTAssertThrowsError(try Inventory.withdraw(10, from: sample, expectedVolume: 100, reason: "  ", in: context))
        sample.archived = true
        XCTAssertThrowsError(try Inventory.withdraw(10, from: sample, expectedVolume: 100, reason: "Assay", in: context))
        sample.archived = false; sample.startingVolumeUL = nil
        XCTAssertThrowsError(try Inventory.withdraw(10, from: sample, expectedVolume: nil, reason: "Assay", in: context))
        XCTAssertTrue(sample.events.isEmpty)
        sample.startingVolumeUL = 100
        try Inventory.withdraw(100, from: sample, expectedVolume: 100, reason: "Used the remaining tube", in: context)
        XCTAssertEqual(sample.remainingUL, 0)
        XCTAssertEqual(sample.takenOutUL(on: Date()), 100)
    }

    @MainActor func testDailyUseFollowsLocalDaysAndRefundsOriginalMeasurementDay() throws {
        let (app, _, sample) = try fixture()
        let context = app.container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12)))
        let midnight = calendar.startOfDay(for: today)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: midnight))
        func record(_ kind: EventKind, _ date: Date?, amount: Double? = nil) throws {
            try Inventory.record(kind, for: sample, amount: amount, notes: "Test", in: context)
            sample.orderedEvents.last?.date = date
        }
        try record(.withdrawal, midnight.addingTimeInterval(-1), amount: 5)
        try record(.withdrawal, midnight, amount: 10)
        try record(.withdrawal, tomorrow.addingTimeInterval(-1), amount: 7)
        try record(.withdrawal, tomorrow, amount: 2)
        try record(.withdrawal, nil, amount: 1)
        try record(.thawWithMeasurement, midnight.addingTimeInterval(-1))
        try record(.thawCountDecrease, today)
        try record(.thawWithMeasurement, today)
        XCTAssertEqual(sample.takenOutUL(on: today, calendar: calendar), 18.5)
        XCTAssertEqual(sample.takenOutUL(on: midnight.addingTimeInterval(-1), calendar: calendar), 5)
        XCTAssertEqual(sample.takenOutUL(on: tomorrow, calendar: calendar), 2)
        try record(.thawCountDecrease, tomorrow)
        XCTAssertEqual(sample.takenOutUL(on: today, calendar: calendar), 17)
        XCTAssertEqual(sample.takenOutUL(on: tomorrow, calendar: calendar), 2)
        try record(.thawWithMeasurement, today)
        try record(.volumeCorrection, today, amount: 40)
        try record(.thawCountDecrease, today)
        // No measurement refund after a measured balance correction.
        XCTAssertEqual(sample.takenOutUL(on: today, calendar: calendar), 18.5)
        XCTAssertEqual(sample.remainingUL, 40)
    }

    func testProteinMassDisplayConvertsMilligramsAndKeepsUnknownSeparateFromZero() {
        XCTAssertEqual(proteinMassLabel(nil), "—")
        XCTAssertEqual(proteinMassLabel(0), "\(number(0)) µg")
        XCTAssertEqual(proteinMassLabel(483.84 * 0.76), "\(number(367.7184)) µg")
        XCTAssertEqual(proteinMassLabel(999.999), "\(number(999.999)) µg")
        XCTAssertEqual(proteinMassLabel(1000), "\(number(1)) mg")
        XCTAssertEqual(proteinMassLabel(593.09 * 4.18), "\(number(2.4791162)) mg")
        XCTAssertEqual(proteinMassLabel(593.09 * 4.18, unit: .micrograms), "\(number(2479.1162)) µg")
        XCTAssertEqual(proteinMassLabel(483.84 * 0.76, unit: .milligrams), "\(number(0.3677184)) mg")
        XCTAssertEqual(proteinMassLabel(0, unit: .milligrams), "\(number(0)) mg")
        for unit in ProteinMassUnit.allCases { XCTAssertEqual(proteinMassLabel(nil, unit: unit), "—") }
    }

    func testThreeDecimalPlaceInputsPreserveUntouchedMeasurements() throws {
        let stored = 483.84000000000003
        XCTAssertEqual(editableNumber(stored), "483.840")
        XCTAssertEqual(editableNumber(1498.5), "1498.500")
        XCTAssertEqual(editableNumber(0.000123456), "0.000")
        XCTAssertEqual(editableNumber(0.76), "0.760")
        XCTAssertEqual(editableNumber(0), "0.000")
        XCTAssertEqual(editableNumber(-12.3456), "-12.346")
        XCTAssertEqual(try editedQuantity("483.840", original: stored, name: "volume"), stored)
        XCTAssertEqual(try editedQuantity("0.000", original: 0.000123456, name: "concentration"), 0.000123456)
        XCTAssertEqual(try editedQuantity("480", original: stored, name: "volume"), 480)
        XCTAssertEqual(try editedQuantity("483.75", original: stored, name: "volume"), 483.75)
        XCTAssertNil(try editedQuantity("", original: stored, name: "concentration", optional: true))
        XCTAssertThrowsError(try editedQuantity("", original: stored, name: "volume"))
        XCTAssertThrowsError(try editedQuantity("-1", original: stored, name: "volume"))
    }
    @MainActor func testAcceptingRoundedVolumeDoesNotCreateAChange() throws {
        let (app, _, sample) = try fixture()
        sample.startingVolumeUL = 483.84000000000003
        try Inventory.save(app.container.mainContext)
        let original = try XCTUnwrap(sample.remainingUL)
        let entered = try XCTUnwrap(editedQuantity(editableNumber(original), original: original, name: "volume"))
        try Inventory.changeValue(.volume, for: sample, to: entered, expected: original,
                                  reason: "Unchanged input", in: app.container.mainContext)
        XCTAssertEqual(sample.remainingUL, original)
        XCTAssertTrue(sample.events.isEmpty)
    }

    @MainActor func testDirectValueChangesRequireReasonsAndKeepBeforeAfterHistory() throws {
        let (app,batch,a)=try fixture();let context=app.container.mainContext
        let start=Date()
        XCTAssertThrowsError(try Inventory.changeValue(.volume,for:a,to:80,expected:100,reason:"  ",in:context))
        XCTAssertEqual(a.remainingUL,100);XCTAssertTrue(a.events.isEmpty)
        try Inventory.changeValue(.volume,for:a,to:80,expected:100,reason:"Took out sample for enzymatic assay",in:context)
        XCTAssertEqual(a.remainingUL,80);XCTAssertEqual(a.events.count,1)
        let use=try XCTUnwrap(a.orderedEvents.last)
        XCTAssertEqual(use.valueBefore,100);XCTAssertEqual(use.valueAfter,80);XCTAssertEqual(use.volumeDeltaUL,-20)
        XCTAssertEqual(use.notes,"Took out sample for enzymatic assay")
        XCTAssertTrue(try XCTUnwrap(use.date)>=start);XCTAssertFalse(use.dateOnly)
        try Inventory.changeValue(.concentration,for:a,to:1.25,expected:2,reason:"Measured again",in:context)
        XCTAssertEqual(a.currentConcentrationMgML,1.25);XCTAssertEqual(a.concentrationMgML,2)
        XCTAssertEqual(a.remainingUL,80);XCTAssertEqual(a.massUG,100)
        XCTAssertEqual(a.orderedEvents.last?.valueBefore,2);XCTAssertEqual(a.orderedEvents.last?.valueAfter,1.25)
        XCTAssertEqual(a.orderedEvents.last?.volumeDeltaUL,0)
        try Inventory.changeValue(.concentration,for:a,to:1.25,expected:1.25,reason:"No change",in:context)
        XCTAssertEqual(a.events.count,2)
        XCTAssertThrowsError(try Inventory.changeValue(.volume,for:a,to:75,expected:100,reason:"Stale edit",in:context))
        for invalid in [-1.0,.nan,.infinity] {
            XCTAssertThrowsError(try Inventory.changeValue(.concentration,for:a,to:invalid,expected:1.25,reason:"Invalid",in:context))
        }
        XCTAssertEqual(a.events.count,2)
        try Inventory.changeValue(.volume,for:a,to:85,expected:80,reason:"Re-measured recovered volume",in:context)
        XCTAssertEqual(a.remainingUL,85)
        a.archived=true;try Inventory.save(context)
        XCTAssertThrowsError(try Inventory.changeValue(.volume,for:a,to:90,expected:85,reason:"Archived",in:context))
        try SampleBackup(batches:[batch]).validate()
    }
    @MainActor func testUnknownValuesCanBeEditedAndBackupHistoryIsValidated() throws {
        let (app,batch,_)=try fixture();let context=app.container.mainContext
        let a=Aliquot(label:"Unknown",volume:nil,concentration:nil,thawCount:nil,state:.unknown,location:"")
        try Inventory.addAliquot(a,to:batch,in:context)
        try Inventory.changeValue(.volume,for:a,to:45,expected:nil,reason:"Recovered after spin",in:context)
        try Inventory.changeValue(.concentration,for:a,to:0,expected:nil,reason:"Measured zero",in:context)
        XCTAssertEqual(a.remainingUL,45);XCTAssertEqual(a.currentConcentrationMgML,0);XCTAssertEqual(a.massUG,0)
        let backup=SampleBackup(batches:[batch]);let index=try XCTUnwrap(backup.batches[0].aliquots.firstIndex { $0.id==a.id })
        let target=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        let decoded=try JSONDecoder().decode(SampleBackup.self,from:backup.data())
        XCTAssertEqual(try decoded.merge(into:target.container.mainContext),1)
        XCTAssertEqual(SampleBackup(batches:try target.container.mainContext.fetch(FetchDescriptor<ProteinBatch>())).batches,backup.batches)
        let restored=try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<Aliquot>()).first { $0.id==a.id })
        XCTAssertEqual(restored.currentConcentrationMgML,0)
        var wrongBefore=backup;wrongBefore.batches[0].aliquots[index].events[1].valueBefore=3
        var wrongVolume=backup;wrongVolume.batches[0].aliquots[index].events[0].valueAfter=90
        var missingReason=backup;missingReason.batches[0].aliquots[index].events[1].notes=""
        var missingValue=backup;missingValue.batches[0].aliquots[index].events[1].valueAfter=nil
        var oldVersion=backup;oldVersion.version=4
        for invalid in [wrongBefore,wrongVolume,missingReason,missingValue,oldVersion] { XCTAssertThrowsError(try invalid.validate()) }
    }
    @MainActor func testThawMeasurementDeductsAndUndoesTogether() throws {
        let (app,batch,a)=try fixture();let context=app.container.mainContext
        try Inventory.record(.thawWithMeasurement,for:a,in:context)
        XCTAssertEqual(a.countedThaws,1);XCTAssertEqual(a.remainingUL,98.5);XCTAssertEqual(a.massUG,197)
        XCTAssertEqual(a.events.count,1);XCTAssertEqual(a.state,.thawed)
        try Inventory.record(.freeze,for:a,in:context)
        XCTAssertEqual(a.remainingUL,98.5);XCTAssertEqual(a.countedThaws,1)
        try Inventory.record(.thawWithMeasurement,for:a,in:context)
        try Inventory.record(.withdrawal,for:a,amount:10,in:context)
        XCTAssertEqual(a.remainingUL,87)
        try Inventory.record(.thawCountDecrease,for:a,in:context)
        XCTAssertEqual(a.remainingUL,88.5);XCTAssertEqual(a.countedThaws,1)
        try Inventory.record(.thawCountDecrease,for:a,in:context)
        XCTAssertEqual(a.remainingUL,90);XCTAssertEqual(a.countedThaws,0)
        XCTAssertThrowsError(try Inventory.record(.thawCountDecrease,for:a,in:context))
        XCTAssertEqual(a.events.count,6)
        try SampleBackup(batches:[batch]).validate()

        let tiny=Aliquot(label:"Last measurement",volume:1.5,concentration:2,thawCount:0,state:.frozen,location:"")
        try Inventory.addAliquot(tiny,to:batch,in:context)
        try Inventory.record(.thawWithMeasurement,for:tiny,in:context)
        XCTAssertEqual(tiny.remainingUL,0);XCTAssertEqual(tiny.countedThaws,1)
        XCTAssertThrowsError(try Inventory.record(.thawWithMeasurement,for:tiny,in:context))
        XCTAssertEqual(tiny.events.count,1);XCTAssertEqual(tiny.countedThaws,1)
        try Inventory.record(.thawCountDecrease,for:tiny,in:context)
        XCTAssertEqual(tiny.remainingUL,1.5);XCTAssertEqual(tiny.countedThaws,0)
        tiny.archived=true;try Inventory.save(context)
        XCTAssertThrowsError(try Inventory.record(.thawWithMeasurement,for:tiny,in:context))
    }
    @MainActor func testMeasurementsPreserveHistoricalAndUnknownBalances() throws {
        let (app,batch,a)=try fixture();let context=app.container.mainContext
        a.startingThawCount=1
        try Inventory.record(.withdrawal,for:a,amount:1.5,notes:"Previously measured",in:context)
        try Inventory.record(.thawCountIncrease,for:a,in:context)
        try Inventory.record(.thawCountDecrease,for:a,in:context)
        try Inventory.record(.thawCountDecrease,for:a,in:context)
        XCTAssertEqual(a.remainingUL,98.5);XCTAssertEqual(a.countedThaws,0)
        try Inventory.record(.thawWithMeasurement,for:a,in:context)
        try Inventory.record(.volumeCorrection,for:a,amount:50,notes:"Measured remaining balance",in:context)
        try Inventory.record(.thawCountDecrease,for:a,in:context)
        XCTAssertEqual(a.remainingUL,50)

        let unknown=Aliquot(label:"Unknown balance",volume:nil,concentration:nil,thawCount:nil,state:.unknown,location:"")
        try Inventory.addAliquot(unknown,to:batch,in:context)
        try Inventory.record(.thawWithMeasurement,for:unknown,in:context)
        XCTAssertNil(unknown.remainingUL);XCTAssertEqual(unknown.thawLabel,"Unknown + 1 recorded")
        XCTAssertEqual(unknown.orderedEvents.last?.volumeDeltaUL,-1.5)
        try Inventory.record(.volumeCorrection,for:unknown,amount:20,notes:"Measured remaining balance",in:context)
        try Inventory.record(.thawCountDecrease,for:unknown,in:context)
        XCTAssertEqual(unknown.remainingUL,20);XCTAssertNil(unknown.startingThawCount)
        try SampleBackup(batches:[batch]).validate()
    }
    @MainActor func testMeasurementBackupRoundTripAndInvalidRefunds() throws {
        let (app,batch,a)=try fixture();let context=app.container.mainContext
        try Inventory.record(.thawWithMeasurement,for:a,in:context)
        try Inventory.record(.thawCountDecrease,for:a,in:context)
        try Inventory.record(.thawWithMeasurement,for:a,in:context)
        let backup=SampleBackup(batches:[batch]);XCTAssertEqual(backup.version,5)
        let target=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        let decoded=try JSONDecoder().decode(SampleBackup.self,from:backup.data())
        XCTAssertEqual(try decoded.merge(into:target.container.mainContext),1)
        let restored=try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<Aliquot>()).first)
        XCTAssertEqual(restored.remainingUL,98.5);XCTAssertEqual(restored.countedThaws,1)
        XCTAssertEqual(restored.nextThawCorrectionVolumeUL,1.5)
        var wrongAmount=backup;wrongAmount.batches[0].aliquots[0].events[0].delta = -3
        var wrongRefund=backup;wrongRefund.batches[0].aliquots[0].events[1].delta = 3
        var forgedRefund=backup;forgedRefund.batches[0].aliquots[0].events[0].kind = .thawCountIncrease
        forgedRefund.batches[0].aliquots[0].events[0].delta=0
        var negative=backup;negative.batches[0].aliquots[0].volume=1
        var oldVersion=backup;oldVersion.version=3
        let empty=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        for invalid in [wrongAmount,wrongRefund,forgedRefund,negative,oldVersion] { XCTAssertThrowsError(try invalid.merge(into:empty.container.mainContext)) }
        XCTAssertEqual(try empty.container.mainContext.fetchCount(FetchDescriptor<ProteinBatch>()),0)
        let legacySource=try fixture()
        try Inventory.record(.thawCountIncrease,for:legacySource.2,in:legacySource.0.container.mainContext)
        legacySource.2.label="Old counter sample"
        var legacy=withExtendedLifetime(legacySource) { SampleBackup(batches:[legacySource.1]) };legacy.version=3
        XCTAssertEqual(try legacy.merge(into:target.container.mainContext),1)
    }
    @MainActor func testThawCounterPreservesHistoryAndUnknownBaseline() throws {
        let (app,batch,unknown)=try fixture();let context=app.container.mainContext
        let known=Aliquot(label:"Counter",volume:50,concentration:2,thawCount:1,state:.unknown,location:"")
        try Inventory.addAliquot(known,to:batch,in:context)
        try Inventory.record(.thawCountDecrease,for:known,in:context)
        XCTAssertEqual(known.countedThaws,0);XCTAssertEqual(known.startingThawCount,1)
        XCTAssertEqual(known.state,.unknown)
        XCTAssertThrowsError(try Inventory.record(.thawCountDecrease,for:known,in:context))
        try Inventory.record(.thawCountIncrease,for:known,in:context)
        try Inventory.record(.thawCountIncrease,for:known,in:context)
        XCTAssertEqual(known.countedThaws,2);XCTAssertEqual(known.state,.thawed)
        try Inventory.record(.freeze,for:known,in:context)
        XCTAssertEqual(known.countedThaws,2);XCTAssertEqual(known.state,.frozen)
        try Inventory.record(.thawCountIncrease,for:known,in:context)
        XCTAssertEqual(known.countedThaws,3);XCTAssertEqual(known.remainingUL,50)
        XCTAssertEqual(known.events.count,5)
        XCTAssertThrowsError(try Inventory.record(.thawCountDecrease,for:unknown,in:context))
        try Inventory.record(.thawCountIncrease,for:unknown,in:context)
        XCTAssertEqual(unknown.thawLabel,"Unknown + 1 recorded")
        try Inventory.record(.thawCountDecrease,for:unknown,in:context)
        XCTAssertEqual(unknown.thawLabel,"Unknown + 0 recorded");XCTAssertNil(unknown.startingThawCount)
        XCTAssertEqual(unknown.state,.thawed)
        known.archived=true;try Inventory.save(context)
        XCTAssertThrowsError(try Inventory.record(.thawCountIncrease,for:known,in:context))
        XCTAssertThrowsError(try Inventory.record(.thawCountDecrease,for:known,in:context))
        let maximum=Aliquot(label:"Maximum",volume:nil,concentration:nil,thawCount:Int.max,state:.frozen,location:"")
        try Inventory.addAliquot(maximum,to:batch,in:context)
        XCTAssertThrowsError(try Inventory.record(.thawCountIncrease,for:maximum,in:context))
        try Inventory.record(.thawCountDecrease,for:maximum,in:context)
        try Inventory.record(.thawCountIncrease,for:maximum,in:context)
        XCTAssertEqual(maximum.countedThaws,Int.max)
        try SampleBackup(batches:[batch]).validate()
    }
    @MainActor func testCounterBackupsRoundTripAndRejectInvalidCorrections() throws {
        let (app,batch,a)=try fixture();let context=app.container.mainContext
        try Inventory.record(.thawCountIncrease,for:a,in:context)
        try Inventory.record(.freeze,for:a,in:context)
        try Inventory.record(.thaw,for:a,in:context)
        try Inventory.record(.thawCountDecrease,for:a,in:context)
        let backup=SampleBackup(batches:[batch]);XCTAssertEqual(backup.version,5)
        let target=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        let decoded=try JSONDecoder().decode(SampleBackup.self,from:backup.data())
        XCTAssertEqual(try decoded.merge(into:target.container.mainContext),1)
        let restored=try XCTUnwrap(target.container.mainContext.fetch(FetchDescriptor<Aliquot>()).first)
        XCTAssertEqual(restored.countedThaws,1);XCTAssertEqual(restored.state,.thawed)
        XCTAssertEqual(SampleBackup(batches:try target.container.mainContext.fetch(FetchDescriptor<ProteinBatch>())).batches,backup.batches)
        let legacySource=try fixture();legacySource.2.label="Legacy sample"
        var legacy=withExtendedLifetime(legacySource) { SampleBackup(batches:[legacySource.1]) };legacy.version=2
        XCTAssertEqual(try legacy.merge(into:target.container.mainContext),1)
        var negative=backup;negative.batches[0].aliquots[0].events[0].kind = .thawCountDecrease
        negative.batches[0].aliquots[0].events[0].state=nil
        var wrongState=backup;wrongState.batches[0].aliquots[0].events[0].state = .frozen
        var wrongVersion=backup;wrongVersion.version=2
        let empty=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        for invalid in [negative,wrongState,wrongVersion] { XCTAssertThrowsError(try invalid.merge(into:empty.container.mainContext)) }
        XCTAssertEqual(try empty.container.mainContext.fetchCount(FetchDescriptor<ProteinBatch>()),0)
    }
    @MainActor func testSingleStepRegistrationIsAtomic() throws {
        let (app,_,_)=try fixture();let context=app.container.mainContext
        let invalidBatch=ProteinBatch(name:"Duplicate attempt")
        let duplicate=Aliquot(label:"DEMO-01",volume:10,concentration:1,thawCount:0,state:.unknown,location:"")
        XCTAssertThrowsError(try Inventory.addSample(duplicate,with:invalidBatch,in:context))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProteinBatch>()),1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Aliquot>()),1)
        let batch=ProteinBatch(name:"New tube",variant:"Cut")
        let tube=Aliquot(label:"New tube",volume:nil,concentration:nil,thawCount:nil,state:.unknown,location:"")
        try Inventory.addSample(tube,with:batch,in:context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProteinBatch>()),2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Aliquot>()),2)
        XCTAssertEqual(tube.batch?.id,batch.id)
        XCTAssertEqual(batch.aliquots.map(\.id),[tube.id])
        XCTAssertNil(tube.remainingUL)
        XCTAssertNil(tube.startingThawCount)
    }
    @MainActor func testUnknownVolumeCanBeMeasuredWithoutInventingAnOpeningBalance() throws {
        let (app,batch,_)=try fixture();let context=app.container.mainContext
        let a=Aliquot(label:"Unknown-volume",volume:nil,concentration:2,thawCount:0,state:.unknown,location:"")
        try Inventory.addAliquot(a,to:batch,in:context)
        XCTAssertNil(a.remainingUL);XCTAssertNil(a.massUG)
        XCTAssertThrowsError(try Inventory.record(.withdrawal,for:a,amount:1,in:context))
        try Inventory.record(.freeze,for:a,in:context)
        XCTAssertNil(a.remainingUL)
        try Inventory.record(.volumeCorrection,for:a,amount:50,notes:"Measured today",in:context)
        XCTAssertNil(a.startingVolumeUL);XCTAssertEqual(a.remainingUL,50)
        XCTAssertEqual(a.orderedEvents.last?.volumeAfterUL,50)
        try Inventory.record(.withdrawal,for:a,amount:10,in:context)
        XCTAssertEqual(a.remainingUL,40);XCTAssertEqual(a.massUG,80)
        let backup=SampleBackup(batches:[batch]);try backup.validate()
        let target=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        XCTAssertEqual(try JSONDecoder().decode(SampleBackup.self,from:backup.data()).merge(into:target.container.mainContext),1)
        XCTAssertEqual(SampleBackup(batches:try target.container.mainContext.fetch(FetchDescriptor<ProteinBatch>())).batches,backup.batches)
    }
    @MainActor func testHistoricalDatesAndOldBackupsRemainSupported() throws {
        let (app,batch,a)=try fixture();let context=app.container.mainContext
        let undated=SampleEvent(sequence:1,date:nil,kind:.withdrawal,delta:-1.5,notes:"Undated historical use")
        context.insert(undated);undated.aliquot=a
        let dated=SampleEvent(sequence:2,date:Date(timeIntervalSinceReferenceDate:100000),dateOnly:true,kind:.withdrawal,delta:-2)
        context.insert(dated);dated.aliquot=a;try Inventory.save(context)
        let backup=SampleBackup(batches:[batch]);try backup.validate()
        let decoded=try JSONDecoder().decode(SampleBackup.self,from:backup.data())
        XCTAssertNil(decoded.batches[0].aliquots[0].events[0].date)
        XCTAssertEqual(decoded.batches[0].aliquots[0].events[1].dateOnly,true)
        let oldSource=try fixture()
        var old=SampleBackup(batches:[oldSource.1]);old.version=1
        let target=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        XCTAssertEqual(try old.merge(into:target.container.mainContext),1)
    }
    @MainActor func testLocalMigrationAndWorkbookImportWhenRequested() throws {
        guard let directory=ProcessInfo.processInfo.environment["PLATELAB_MIGRATION_DIRECTORY"],let file=ProcessInfo.processInfo.environment["PLATELAB_IMPORT_CHECK"] else { throw XCTSkip("Set local fixture paths to check an existing database migration and import.") }
        let app=try AppState(directory:URL(fileURLWithPath:directory))
        let old=try app.container.mainContext.fetch(FetchDescriptor<Aliquot>())
        XCTAssertFalse(old.isEmpty)
        let previous=SampleBackup(batches:try app.container.mainContext.fetch(FetchDescriptor<ProteinBatch>())).batches
        let backup=try JSONDecoder().decode(SampleBackup.self,from:Data(contentsOf:URL(fileURLWithPath:file)))
        let before=old.count
        XCTAssertEqual(try backup.merge(into:app.container.mainContext),backup.batches.count)
        XCTAssertEqual(try backup.merge(into:app.container.mainContext),0)
        XCTAssertEqual(try app.container.mainContext.fetchCount(FetchDescriptor<Aliquot>()),before+backup.batches.reduce(0) { $0+$1.aliquots.count })
        XCTAssertEqual(SampleBackup(batches:try app.container.mainContext.fetch(FetchDescriptor<ProteinBatch>())).batches.filter { backup.batches.map(\.id).contains($0.id) },backup.batches)
        XCTAssertEqual(SampleBackup(batches:try app.container.mainContext.fetch(FetchDescriptor<ProteinBatch>())).batches.filter { previous.map(\.id).contains($0.id) },previous)
    }
    @MainActor func fixture() throws -> (AppState, ProteinBatch, Aliquot) {
        let app=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        let batch=ProteinBatch(name:"Demo protein",variant:"Test only",concentration:2,buffer:"Test buffer")
        try Inventory.addBatch(batch,in:app.container.mainContext)
        let tube=Aliquot(label:"DEMO-01",volume:100,concentration:2,thawCount:nil,state:.frozen,location:"Test freezer · A1")
        try Inventory.addAliquot(tube,to:batch,in:app.container.mainContext)
        return (app,batch,tube)
    }
    @MainActor func testWithdrawalsAndCorrectionsPreserveHistory() throws {
        let (app,_,a)=try fixture();let context=app.container.mainContext
        try Inventory.record(.withdrawal,for:a,amount:15,experiment:"Test plate",plateID:"test-plate",wells:"A1, A2",in:context)
        XCTAssertEqual(a.remainingUL,85);XCTAssertEqual(a.massUG,170)
        XCTAssertEqual(a.events.first?.plateID,"test-plate")
        for invalid in [0.0,-1,86,.infinity,.nan] {
            XCTAssertThrowsError(try Inventory.record(.withdrawal,for:a,amount:invalid,in:context))
        }
        XCTAssertEqual(a.events.count,1);XCTAssertEqual(a.remainingUL,85)
        XCTAssertThrowsError(try Inventory.record(.volumeCorrection,for:a,amount:80,in:context))
        try Inventory.record(.volumeCorrection,for:a,amount:80,notes:"Measured again",in:context)
        XCTAssertEqual(a.remainingUL,80);XCTAssertEqual(a.orderedEvents.last?.volumeDeltaUL,-5)
        try Inventory.record(.withdrawal,for:a,amount:80,in:context)
        XCTAssertEqual(a.remainingUL,0)
    }
    @MainActor func testThawTransitionsAndIndependentAliquots() throws {
        let (app,batch,a)=try fixture();let context=app.container.mainContext
        let b=Aliquot(label:"DEMO-02",volume:50,concentration:nil,thawCount:2,state:.frozen,location:"A2")
        try Inventory.addAliquot(b,to:batch,in:context)
        XCTAssertEqual(a.thawLabel,"Unknown + 0 recorded")
        XCTAssertThrowsError(try Inventory.record(.freeze,for:a,in:context))
        try Inventory.record(.thaw,for:a,in:context)
        XCTAssertEqual(a.state,.thawed);XCTAssertEqual(a.thawLabel,"Unknown + 1 recorded")
        XCTAssertThrowsError(try Inventory.record(.thaw,for:a,in:context))
        try Inventory.record(.freeze,for:a,in:context)
        XCTAssertEqual(a.recordedThaws,1)
        try Inventory.record(.thaw,for:b,in:context)
        XCTAssertEqual(b.thawLabel,"3");XCTAssertEqual(a.recordedThaws,1)
        try Inventory.record(.withdrawal,for:a,amount:10,in:context)
        XCTAssertEqual(b.remainingUL,50)
        try Inventory.record(.moved,for:b,location:"Box B · 2",in:context)
        XCTAssertEqual(b.location,"Box B · 2")
        a.archived=true;try Inventory.save(context)
        XCTAssertThrowsError(try Inventory.record(.withdrawal,for:a,amount:1,in:context))
    }
    @MainActor func testRegistrationValidation() throws {
        let (app,batch,_)=try fixture();let context=app.container.mainContext
        let duplicate=Aliquot(label:" demo-01 ",volume:10,concentration:1,thawCount:0,state:.unknown,location:"")
        XCTAssertThrowsError(try Inventory.addAliquot(duplicate,to:batch,in:context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Aliquot>()),1)
        XCTAssertThrowsError(try quantity("NaN",name:"volume"))
        XCTAssertThrowsError(try quantity("-1",name:"volume"))
        XCTAssertNil(try quantity("",name:"concentration",optional:true))
        XCTAssertEqual(try quantity("0",name:"concentration",optional:true),0)
    }
    @MainActor func testBackupRoundTripAndConflictsAreAtomic() throws {
        let (app,batch,a)=try fixture();let context=app.container.mainContext
        try Inventory.record(.thaw,for:a,in:context)
        try Inventory.record(.withdrawal,for:a,amount:12.5,notes:"Test transfer",experiment:"Demo plate",plateID:"demo",wells:"B1, B2",in:context)
        let backup=SampleBackup(batches:[batch])
        let decoded=try JSONDecoder().decode(SampleBackup.self,from:backup.data())
        let target=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        XCTAssertEqual(try decoded.merge(into:target.container.mainContext),1)
        XCTAssertEqual(try decoded.merge(into:target.container.mainContext),0)
        let restored=SampleBackup(batches:try target.container.mainContext.fetch(FetchDescriptor<ProteinBatch>()))
        XCTAssertEqual(restored.batches,backup.batches)
        var conflict=decoded;conflict.batches[0].aliquots[0].volume=999
        XCTAssertThrowsError(try conflict.merge(into:target.container.mainContext))
        XCTAssertEqual(SampleBackup(batches:try target.container.mainContext.fetch(FetchDescriptor<ProteinBatch>())).batches,restored.batches)
        if let output=ProcessInfo.processInfo.environment["PLATELAB_TEST_BACKUP"] { try backup.data().write(to:URL(fileURLWithPath:output)) }
    }
    @MainActor func testMalformedBackupsRejectedBeforeWriting() throws {
        let (app,batch,a)=try fixture()
        try Inventory.record(.withdrawal,for:a,amount:10,in:app.container.mainContext)
        let original=SampleBackup(batches:[batch])
        var negative=original;negative.batches[0].aliquots[0].events[0].delta = -101
        var duplicate=original;duplicate.batches.append(original.batches[0])
        var transition=original;transition.batches[0].aliquots[0].events[0].kind = .thaw
        var nonfinite=original;nonfinite.batches[0].aliquots[0].volume = .infinity
        var badSequence=original;badSequence.batches[0].aliquots[0].events[0].sequence=5
        let target=try AppState(directory:FileManager.default.temporaryDirectory,memory:true)
        for invalid in [negative,duplicate,transition,nonfinite,badSequence] { XCTAssertThrowsError(try invalid.merge(into:target.container.mainContext)) }
        XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<ProteinBatch>()),0)
    }
    @MainActor func testDiskReopenAndPlateStorageDoNotDeductSamples() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("PlateLab-tests-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        var app: AppState?=try AppState(directory:directory)
        do {
            let context=app!.container.mainContext
            let batch=ProteinBatch(name:"Persistent sample")
            try Inventory.addBatch(batch,in:context)
            let a=Aliquot(label:"P-01",volume:40,concentration:nil,thawCount:0,state:.frozen,location:"Box A")
            try Inventory.addAliquot(a,to:batch,in:context)
            try Inventory.record(.withdrawal,for:a,amount:7,in:context)
            try Inventory.record(.thawWithMeasurement,for:a,in:context)
            try Inventory.record(.thawWithMeasurement,for:a,in:context)
            try Inventory.record(.thawCountDecrease,for:a,in:context)
            try Inventory.changeValue(.concentration,for:a,to:1.5,expected:nil,reason:"New measurement",in:context)
            try app!.writeJSON(["version":1,"projects":[],"active":NSNull()] as [String:Any],name:"plates.json")
            XCTAssertEqual(a.remainingUL,31.5)
        }
        app=nil
        let reopened=try AppState(directory:directory)
        let a=try XCTUnwrap(reopened.container.mainContext.fetch(FetchDescriptor<Aliquot>()).first)
        XCTAssertEqual(a.remainingUL,31.5);XCTAssertEqual(a.events.count,5);XCTAssertEqual(a.thawLabel,"1")
        XCTAssertEqual(a.currentConcentrationMgML,1.5);XCTAssertEqual(a.massUG,47.25)
        let plates=try XCTUnwrap(reopened.readJSON("plates.json",fallback:[:]) as? [String:Any])
        XCTAssertEqual(plates["version"] as? Int,1)
    }
}
