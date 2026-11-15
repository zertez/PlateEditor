import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct PlateWorkspaceView: View {
    @EnvironmentObject var app: AppState
    @State private var transfer: TransferContext?
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Label("Plate editor",systemImage:"square.grid.3x3").font(.headline)
                Text("Offline · saved on this Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    transfer=TransferContext(plateID:app.currentPlateID,title:app.currentPlateTitle,wells:app.currentWells)
                } label: { Label("Record completed sample transfer…",systemImage:"arrow.down.right.circle") }.disabled(app.currentPlateID==nil)
            }.padding(14)
            Divider()
            PlateWebView(app:app)
        }.sheet(item:$transfer) { context in TransferPicker(plateID:context.plateID,plateTitle:context.title,wells:context.wells).environmentObject(app) }
    }
}
struct TransferContext: Identifiable {
    let id=UUID()
    let plateID: String?
    let title: String
    let wells: [String]
}
struct PlateWebView: NSViewRepresentable {
    let app: AppState
    func makeCoordinator() -> Coordinator { Coordinator(app:app) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addScriptMessageHandler(context.coordinator,contentWorld:.page,name:"plateLab")
        let bridge="""
        (() => {
          const request = (type, body = {}) => window.webkit.messageHandlers.plateLab.postMessage({type, ...body});
          window.PlateLab = {
            load: () => request('load'),
            saveLibrary: library => request('saveLibrary', {library}),
            saveDisplay: display => request('saveDisplay', {display}),
            selection: (id, title, wells) => request('selection', {id, title, wells}),
            exportText: (text, filename, mime) => request('export', {text, filename, mime})
          };
          window.print = () => request('print').catch(error => window.alert(error.message || String(error)));
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source:bridge,injectionTime:.atDocumentStart,forMainFrameOnly:true))
        let view=WKWebView(frame:.zero,configuration:configuration)
        view.navigationDelegate=context.coordinator;view.uiDelegate=context.coordinator;context.coordinator.webView=view
        if let root=Bundle.main.resourceURL?.appendingPathComponent("Web",isDirectory:true),FileManager.default.fileExists(atPath:root.appendingPathComponent("index.html").path) {
            context.coordinator.webRoot=root.standardizedFileURL
            view.loadFileURL(root.appendingPathComponent("index.html"),allowingReadAccessTo:root)
        } else { DispatchQueue.main.async { app.error="The bundled plate editor is missing. Build PlateLab with native/macOS/Scripts/build-app.sh." } }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { view.configuration.userContentController.removeScriptMessageHandler(forName:"plateLab",contentWorld:.page) }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply {
        let app: AppState
        weak var webView: WKWebView?
        var webRoot: URL?
        init(app: AppState) { self.app=app }
        func trusted(_ url: URL?) -> Bool {
            guard let url,let root=webRoot,url.isFileURL else { return false }
            return url.standardizedFileURL.path.hasPrefix(root.path+"/")
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?,String?)->Void) {
            guard message.frameInfo.isMainFrame,trusted(message.frameInfo.request.url),let body=message.body as? [String:Any],let type=body["type"] as? String else { replyHandler(nil,"Untrusted request.");return }
            do {
                switch type {
                case "load":
                    let library=try app.readJSON("plates.json",fallback:["version":1,"projects":[],"active":NSNull()] as [String:Any])
                    let display=try app.readJSON("plate-display.json",fallback:[:])
                    replyHandler(["library":library,"display":display],nil);return
                case "saveLibrary":
                    guard let library=body["library"] as? [String:Any],library["version"] as? Int == 1,library["projects"] is [[String:Any]] else { throw LabError("The plate library could not be validated. Existing data was not overwritten.") }
                    try app.writeJSON(library,name:"plates.json")
                case "saveDisplay":
                    guard let display=body["display"] as? [String:Any] else { throw LabError("Invalid display preferences.") };try app.writeJSON(display,name:"plate-display.json")
                case "selection":
                    app.currentPlateID=body["id"] as? String;app.currentPlateTitle=body["title"] as? String ?? "";app.currentWells=body["wells"] as? [String] ?? []
                case "export":
                    guard let text=body["text"] as? String,let filename=body["filename"] as? String else { throw LabError("Nothing to export.") }
                    let fileType: UTType? = filename.hasSuffix(".csv") ? .commaSeparatedText:filename.hasSuffix(".json") ? .json:nil
                    try app.saveFile(data:Data(text.utf8),suggestedName:filename,type:fileType)
                case "print":
                    guard let webView else { throw LabError("The plate editor is not ready to print.") }
                    let info=NSPrintInfo.shared.copy() as! NSPrintInfo
                    info.paperSize=NSSize(width:595.28,height:841.89);info.orientation = .landscape
                    info.topMargin=34;info.bottomMargin=34;info.leftMargin=34;info.rightMargin=34
                    let operation=webView.printOperation(with:info);operation.showsPrintPanel=true;operation.showsProgressPanel=true;operation.run()
                default: throw LabError("Unsupported app request.")
                }
                replyHandler(NSNull(),nil)
            } catch { replyHandler(nil,error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
            guard let url=navigationAction.request.url else { decisionHandler(.cancel);return }
            if trusted(url) || url.scheme=="about" { decisionHandler(.allow) }
            else if ["https","http"].contains(url.scheme ?? ""),navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url);decisionHandler(.cancel) }
            else { decisionHandler(.cancel) }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { app.error=error.localizedDescription }
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?)->Void) {
            let panel=NSOpenPanel();panel.allowsMultipleSelection=parameters.allowsMultipleSelection;panel.canChooseDirectories=false;panel.canChooseFiles=true
            completionHandler(panel.runModal() == .OK ? panel.urls:nil)
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ()->Void) {
            let alert=NSAlert();alert.messageText="PlateLab";alert.informativeText=message;alert.runModal();completionHandler()
        }
    }
}
