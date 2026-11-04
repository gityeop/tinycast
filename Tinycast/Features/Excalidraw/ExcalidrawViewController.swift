import AppKit
import OSLog
import WebKit

@MainActor
final class ExcalidrawViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private static let logger = Logger(subsystem: "com.gityeop.tinycast", category: "Excalidraw")
    let webView: WKWebView
    private let url: URL
    private let onFailure: (String) -> Void
    private let status = NSTextField(labelWithString: "Loading Excalidraw…")
    private let progress = NSProgressIndicator()
    private let retry = NSButton(title: "Reload", target: nil, action: nil)
    private var isReady = false
    private var downloads: [ObjectIdentifier: (temporary: URL, destination: URL)] = [:]

    init(
        url: URL, dataStore: WKWebsiteDataStore = .default(),
        onFailure: @escaping (String) -> Void
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.setURLSchemeHandler(
            ExcalidrawAssetsHandler(directory: url.deletingLastPathComponent()),
            forURLScheme: ExcalidrawAssetsHandler.scheme)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.oncastAppearance = '\(dark ? "dark" : "light")';",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.url = url
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = NSColor(Theme.Colors.excalidrawCanvas)
        configuration.userContentController.add(ScriptHandler { [weak self] message in
            self?.receive(message)
        }, name: "excalidraw")
    }

    required init?(coder: NSCoder) { nil }

    func agentRequest(_ request: CanvasRequest) async throws -> String {
        guard isReady else {
            throw NSError(domain: "CanvasMCP", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The Oncast canvas is still loading. Read it again when the editor is ready."
            ])
        }
        let result = try await webView.callAsyncJavaScript("""
        try {
          const value = await window.oncastEditor.agent.request(operation, JSON.parse(input));
          return JSON.stringify({ result: JSON.stringify(value) });
        } catch (error) {
          return JSON.stringify({ error: String(error.message) });
        }
        """, arguments: ["operation": request.operation.rawValue, "input": request.arguments], in: nil, contentWorld: .page)
        guard let json = result as? String,
            let reply = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
        else { throw URLError(.cannotParseResponse) }
        if let error = reply["error"] {
            throw NSError(domain: "CanvasMCP", code: 2, userInfo: [NSLocalizedDescriptionKey: error])
        }
        guard let value = reply["result"] else { throw URLError(.cannotParseResponse) }
        return value
    }

    override func loadView() {
        let surface = SurfaceView()
        surface.onAppearanceChange = { [weak self] in self?.applyAppearance() }
        view = surface
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        retry.target = self
        retry.action = #selector(reload)
        retry.bezelStyle = .rounded
        retry.isHidden = true
        let loading = NSStackView(views: [progress, status, retry])
        loading.orientation = .vertical
        loading.spacing = Theme.Spacing.md
        loading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loading)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        reload()
    }

    @objc func reload() {
        webView.isHidden = true
        isReady = false
        status.stringValue = "Loading Excalidraw…"
        status.isHidden = false
        retry.isHidden = true
        progress.startAnimation(nil)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        applyAppearance()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        pageFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        pageFailed(error)
    }

    private func pageFailed(_ error: Error) {
        webView.isHidden = true
        progress.stopAnimation(nil)
        status.stringValue = "Could not open Excalidraw. Please try loading it again."
        status.isHidden = false
        retry.isHidden = false
        Self.logger.error("Page load failed: \(error.localizedDescription, privacy: .public)")
    }

    private func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: String],
            let kind = body["kind"]
        else { return }
        switch kind {
        case "ready":
            isReady = true
            webView.isHidden = false
            progress.stopAnimation(nil)
            status.isHidden = true
            retry.isHidden = true
            applyAppearance()
        case "error":
            pageFailed(NSError(domain: "Excalidraw", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: body["message", default: "Editor error"]]))
        case "saveError":
            Self.logger.error("Scene save failed: \(body["message", default: "Unknown error"], privacy: .public)")
            onFailure("Could not save the drawing. Please export it to a file.")
        case "copyMCPConfiguration":
            do {
                let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OncastCanvasMCP")
                let configuration = try CanvasEndpoint.configuration(helperURL: helper)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(configuration, forType: .string)
            } catch {
                Self.logger.error("MCP configuration copy failed: \(error.localizedDescription, privacy: .public)")
                onFailure("Could not copy the AI agent connection settings.")
            }
        default: break
        }
    }

    private func applyAppearance() {
        guard isReady else { return }
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        webView.evaluateJavaScript("window.oncastEditor.setTheme('\(dark ? "dark" : "light")')") { _, error in
            if let error { Self.logger.error("Theme update failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private final class ScriptHandler: NSObject, WKScriptMessageHandler {
        let receive: (WKScriptMessage) -> Void
        init(receive: @escaping (WKScriptMessage) -> Void) { self.receive = receive }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            receive(message)
        }
    }

    private final class SurfaceView: NSView {
        var onAppearanceChange: (() -> Void)?
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            onAppearanceChange?()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onAppearanceChange?()
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        navigationAction.shouldPerformDownload ? .download : .allow
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo
    ) async -> [URL]? {
        guard let window = webView.window else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        guard await panel.beginSheetModal(for: window) == .OK else { return nil }
        return panel.urls
    }

    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard let window = webView.window else { return nil }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        guard await panel.beginSheetModal(for: window) == .OK, let destination = panel.url else {
            return nil
        }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("oncast-excalidraw-\(UUID().uuidString)")
        downloads[ObjectIdentifier(download)] = (temporary, destination)
        return temporary
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        do {
            if FileManager.default.fileExists(atPath: file.destination.path) {
                _ = try FileManager.default.replaceItemAt(file.destination, withItemAt: file.temporary)
            } else {
                try FileManager.default.moveItem(at: file.temporary, to: file.destination)
            }
        } catch {
            reportDownloadFailure(error)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
        reportDownloadFailure(error)
    }

    private func reportDownloadFailure(_ error: Error) {
        Self.logger.error("Download failed: \(error.localizedDescription, privacy: .public)")
        onFailure("Could not save the Excalidraw file. Please try exporting again.")
    }
}
