import AppKit
import OSLog

@MainActor
final class ExcalidrawCoordinator {
    private let window: AppWindowController
    private let onFailure: (String) -> Void
    private weak var editor: ExcalidrawViewController?
    private var server: CanvasSocketServer?

    init(activation: ActivationPolicy, onFailure: @escaping (String) -> Void) {
        self.onFailure = onFailure
        window = AppWindowController(
            title: "Excalidraw", contentSize: Theme.Size.excalidrawWindow,
            minimumSize: Theme.Size.excalidrawWindowMinimum, resizable: true,
            autosaveName: "ExcalidrawWindow", activation: activation)
    }

    func show() {
        guard !window.focus() else { return }
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Excalidraw") else {
            Logger(subsystem: "com.gityeop.tinycast", category: "Excalidraw")
                .error("The embedded Excalidraw resource is missing")
            onFailure("Could not open Excalidraw. Please reinstall Oncast.")
            return
        }
        let editor = ExcalidrawViewController(url: url, onFailure: onFailure)
        self.editor = editor
        window.show(chrome: ExcalidrawWindowChrome()) { editor }
        startAgentAccess()
    }

    func closeWindowIfKey() -> Bool {
        guard NSApp.keyWindow?.identifier == ExcalidrawWindowChrome.windowIdentifier else {
            return false
        }
        window.close()
        return true
    }

    func stop() { server?.stop() }

    private func startAgentAccess() {
        guard server == nil else { return }
        let server = CanvasSocketServer(
            handle: { [weak self] request in
                guard let editor = self?.editor else {
                    throw NSError(domain: "CanvasMCP", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "No canvas is open. Open Excalidraw in Oncast first."
                    ])
                }
                return try await editor.agentRequest(request)
            },
            report: { [weak self] error in self?.reportAgentFailure(error) })
        do {
            try server.start()
            self.server = server
        } catch { reportAgentFailure(error) }
    }

    private func reportAgentFailure(_ error: Error) {
        Logger(subsystem: CanvasEndpoint.bundleID, category: "CanvasMCP")
            .error("Agent server failed: \(error.localizedDescription, privacy: .public)")
        onFailure("Could not start AI agent access. Close other Oncast instances and reopen this canvas.")
    }
}
