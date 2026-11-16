import SwiftUI
import SwiftData

@MainActor final class Bootstrap: ObservableObject {
    let state: AppState?
    let failure: String?
    init() {
        do {
            let args=ProcessInfo.processInfo.arguments
            let index=args.firstIndex(of:"--data-directory")
            let directory=index.flatMap { $0+1<args.count ? URL(fileURLWithPath:args[$0+1],isDirectory:true):nil }
            state=try AppState(directory:directory);failure=nil
        } catch { state=nil;failure=error.localizedDescription }
    }
}
@main struct PlateLabApp: App {
    @StateObject private var bootstrap=Bootstrap()
    init() {
        // Keep native windows, sheets, file panels, and the embedded editor in light mode.
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }
    var body: some Scene {
        Window("PlateLab", id: "main") {
            if let state=bootstrap.state {
                RootView().environmentObject(state).modelContainer(state.container)
                    .frame(minWidth:1060,minHeight:680).tint(Color(nsColor: .systemTeal))
            } else {
                VStack(alignment:.leading,spacing:18) {
                    Text("PlateLab could not open its library").font(.title2.bold())
                    Text(bootstrap.failure ?? "Unknown error").textSelection(.enabled)
                    Text("Existing data has been left in place. No replacement library was created.").foregroundStyle(.secondary)
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }.padding(35).frame(width:560)
            }
        }
        .defaultSize(width:1320,height:860)
        .commands {
            CommandGroup(after:.newItem) {
                Button("Import samples backup…") { bootstrap.state?.importSamples() }
                Button("Export samples backup…") { bootstrap.state?.exportSamples() }.keyboardShortcut("s",modifiers:[.command,.shift])
                Button("Export sample inventory CSV…") { bootstrap.state?.exportCSV() }
            }
        }
    }
}
struct RootView: View {
    @EnvironmentObject var app: AppState
    @Query private var aliquots: [Aliquot]
    var body: some View {
        NavigationSplitView {
            VStack(alignment:.leading,spacing:0) {
                Label("PlateLab",systemImage:"flask.fill").font(.title2.weight(.semibold)).padding(20)
                List(AppState.Section.allCases,selection:$app.section) { section in
                    Label(section.rawValue,systemImage:section.symbol).tag(section)
                }.listStyle(.sidebar)
                VStack(alignment:.leading,spacing:7) {
                    Text("\(aliquots.filter { !$0.archived }.count) samples").font(.subheadline)
                    Label("Saved on this Mac",systemImage:"internaldrive").font(.caption).foregroundStyle(.secondary)
                    Menu("Backups & export") {
                        Button("Export samples backup…",action:app.exportSamples)
                        Button("Import samples backup…",action:app.importSamples)
                        Button("Export inventory CSV…",action:app.exportCSV)
                        Button("Show data folder") { NSWorkspace.shared.open(app.dataDirectory) }
                    }.menuStyle(.borderlessButton)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min:180,ideal:200,max:240)
        } detail: {
            ZStack {
                SampleLibraryView().opacity(app.section == .samples ? 1:0).allowsHitTesting(app.section == .samples).accessibilityHidden(app.section != .samples)
                SampleLogsView().opacity(app.section == .logs ? 1:0).allowsHitTesting(app.section == .logs).accessibilityHidden(app.section != .logs)
                PlateWorkspaceView().opacity(app.section == .plates ? 1:0).allowsHitTesting(app.section == .plates).accessibilityHidden(app.section != .plates)
            }
        }
        .disabled(app.valueEdit != nil)
        .accessibilityHidden(app.valueEdit != nil)
        .overlay {
            if let edit = app.valueEdit {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                        .contentShape(Rectangle()).onTapGesture { }
                        .accessibilityHidden(true)
                    SampleValueEditor(sample: edit.sample, action: edit.action) { app.valueEdit = nil }
                        .id(edit.id)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.7)))
                        .shadow(color: .black.opacity(0.16), radius: 24, y: 8)
                        .accessibilityAddTraits(.isModal)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Could not complete that action",isPresented:Binding(get:{app.error != nil},set:{if !$0 {app.error=nil}})) { Button("OK",role:.cancel) { app.error=nil } } message: { Text(app.error ?? "") }
        .alert("PlateLab",isPresented:Binding(get:{app.notice != nil},set:{if !$0 {app.notice=nil}})) { Button("OK",role:.cancel) { app.notice=nil } } message: { Text(app.notice ?? "") }
    }
}
