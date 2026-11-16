import XCTest
import SwiftData
@testable import PlateLab

final class InventoryTests: XCTestCase {
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
        let backup=SampleBackup(batches:[batch]);XCTAssertEqual(backup.version,4)
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
        let backup=SampleBackup(batches:[batch]);XCTAssertEqual(backup.version,4)
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
            try app!.writeJSON(["version":1,"projects":[],"active":NSNull()] as [String:Any],name:"plates.json")
            XCTAssertEqual(a.remainingUL,31.5)
        }
        app=nil
        let reopened=try AppState(directory:directory)
        let a=try XCTUnwrap(reopened.container.mainContext.fetch(FetchDescriptor<Aliquot>()).first)
        XCTAssertEqual(a.remainingUL,31.5);XCTAssertEqual(a.events.count,4);XCTAssertEqual(a.thawLabel,"1")
        let plates=try XCTUnwrap(reopened.readJSON("plates.json",fallback:[:]) as? [String:Any])
        XCTAssertEqual(plates["version"] as? Int,1)
    }
}
