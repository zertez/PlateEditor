import Foundation
import AppKit
import SwiftData
import UniformTypeIdentifiers

@MainActor final class AppState: ObservableObject {
    let container: ModelContainer
    let dataDirectory: URL
    @Published var valueEdit: SampleValueEdit?
    @Published var error: String?
    @Published var notice: String?
    @Published var section: Section = .samples
    @Published var currentPlateID: String?
    @Published var currentPlateTitle = ""
    @Published var currentWells: [String] = []
    enum Section: String, CaseIterable, Identifiable {
        case samples = "Samples", logs = "Logs", plates = "Plates"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .samples: "shippingbox"
            case .logs: "clock.arrow.circlepath"
            case .plates: "square.grid.3x3"
            }
        }
    }
    init(directory: URL? = nil, memory: Bool = false) throws {
        let base=try directory ?? FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("PlateLab",isDirectory:true)
        dataDirectory=base
        if !memory { try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true) }
        let schema=Schema([ProteinBatch.self,Aliquot.self,SampleEvent.self])
        let config = memory ? ModelConfiguration(schema:schema,isStoredInMemoryOnly:true,cloudKitDatabase:.none) : ModelConfiguration("PlateLab",schema:schema,url:base.appendingPathComponent("Samples.store"),cloudKitDatabase:.none)
        container=try ModelContainer(for:schema,configurations:[config]);container.mainContext.autosaveEnabled=false
    }
    func readJSON(_ name: String, fallback: Any) throws -> Any {
        let path=dataDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath:path.path) else { return fallback }
        return try JSONSerialization.jsonObject(with:Data(contentsOf:path))
    }
    func writeJSON(_ value: Any, name: String) throws {
        let data=try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:dataDirectory.appendingPathComponent(name),options:.atomic)
    }
    func exportSamples() {
        do {
            let backup=SampleBackup(batches:try container.mainContext.fetch(FetchDescriptor<ProteinBatch>()))
            try saveFile(data:backup.data(),suggestedName:"PlateLab-samples-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json",type:.json)
        } catch { self.error=error.localizedDescription }
    }
    func importSamples() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false;panel.message="Import a PlateLab sample backup. Identical records are skipped; conflicting history is never overwritten."
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { let backup=try JSONDecoder().decode(SampleBackup.self,from:Data(contentsOf:url));let count=try backup.merge(into:container.mainContext);notice="Imported \(count) protein batches." } catch { self.error=error.localizedDescription }
    }
    func exportCSV() {
        do {
            let aliquots=try container.mainContext.fetch(FetchDescriptor<Aliquot>())
            func cell(_ string: String) -> String { let safe=["=","+","-","@"].contains(String(string.prefix(1))) ? "'"+string : string;return "\""+safe.replacingOccurrences(of:"\"",with:"\"\"")+"\"" }
            var rows=[["Tube ID","Group","Protein","Variant","Batch","Remaining µL","Concentration mg/mL","Protein remaining µg","Starting thaw count","Recorded thaws","Thaw count corrections (-1)","Current thaw count","Current state","Location","Archived","Notes"]]
            rows += aliquots.sorted { $0.label < $1.label }.map { a in [a.label,a.groupName ?? "",a.batch?.name ?? "",a.batch?.variant ?? "",a.batch?.batchLabel ?? "",a.remainingUL.map { String($0) } ?? "Unknown",a.currentConcentrationMgML.map(String.init(describing:)) ?? "",a.massUG.map(String.init(describing:)) ?? "",a.startingThawCount.map(String.init) ?? "Unknown",String(a.recordedThaws),String(a.thawCorrections),a.thawLabel,a.state.rawValue,a.location,a.archived ? "Yes":"No",a.notes] }
            try saveFile(data:Data(rows.map { $0.map(cell).joined(separator:",") }.joined(separator:"\r\n").utf8),suggestedName:"PlateLab-samples.csv",type:.commaSeparatedText)
        } catch { self.error=error.localizedDescription }
    }
    func saveFile(data: Data, suggestedName: String, type: UTType? = nil) throws {
        let panel=NSSavePanel();panel.nameFieldStringValue=(suggestedName as NSString).lastPathComponent
        if let type { panel.allowedContentTypes=[type] }
        guard panel.runModal() == .OK,let url=panel.url else { return }
        try data.write(to:url,options:.atomic)
    }
}
