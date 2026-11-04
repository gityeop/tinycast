import AppKit
import SwiftUI
import WebKit

@main
@MainActor
struct ExcalidrawTests {
    static var failures = 0

    static func check(_ name: String, _ condition: Bool) {
        if !condition { failures += 1 }
        let result = condition ? "PASS" : "FAIL"
        FileHandle.standardOutput.write(Data("\(result): \(name)\n".utf8))
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Task {
            do {
                if let path = ProcessInfo.processInfo.environment["ONCAST_TEST_CANVAS_SOCKET"] {
                    try await serveAgentTest(socket: URL(filePath: path))
                } else {
                    try await runTests()
                }
                exit(failures > 0 ? 1 : 0)
            } catch {
                FileHandle.standardOutput.write(Data("FAIL: \(error)\n".utf8))
                exit(1)
            }
        }
        NSApp.run()
    }

    static var editorURL: URL {
        URL(filePath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tinycast/Resources/Excalidraw/index.html")
    }

    static func runTests() async throws {
        let identifier = UUID()
        try await editAndSave(identifier: identifier)
        try await reopen(identifier: identifier)
        try await Task.sleep(for: .milliseconds(100))
        try await WKWebsiteDataStore.remove(forIdentifier: identifier)
    }

    static func serveAgentTest(socket: URL) async throws {
        let identifier = UUID()
        let (editor, panel) = open(identifier: identifier)
        let server = CanvasSocketServer(
            socketURL: socket,
            handle: { [weak editor] request in
                guard let editor else { throw URLError(.resourceUnavailable) }
                return try await editor.agentRequest(request)
            }, report: { error in check(error.localizedDescription, false) })
        defer {
            server.stop()
            panel.contentViewController = nil
            panel.close()
        }
        guard try await ready(editor) else { return }
        try server.start()
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: socket.path) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try Data("ready".utf8).write(to: socket.appendingPathExtension("ready"), options: .atomic)
        for _ in 0..<600 {
            if FileManager.default.fileExists(atPath: socket.appendingPathExtension("done").path) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw URLError(.timedOut)
    }

    static func open(identifier: UUID) -> (ExcalidrawViewController, NSPanel) {
        let editor = ExcalidrawViewController(
            url: editorURL, dataStore: WKWebsiteDataStore(forIdentifier: identifier),
            onFailure: { message in check(message, false) })
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Excalidraw"
        panel.appearance = NSAppearance(named: .aqua)
        panel.isReleasedWhenClosed = false
        ExcalidrawWindowChrome().install(in: panel)
        panel.contentViewController = editor
        panel.setContentSize(NSSize(width: 1200, height: 800))
        if ProcessInfo.processInfo.environment["ONCAST_TEST_EXCALIDRAW_HOLD_SECONDS"] != nil {
            panel.orderBack(nil)
        }
        return (editor, panel)
    }

    static func editAndSave(identifier: UUID) async throws {
        let (editor, panel) = open(identifier: identifier)
        defer { panel.contentViewController = nil; panel.close() }
        guard try await ready(editor) else { return }
        check("editor loads from the app's bundled resources", editor.webView.url?.isFileURL == true)
        check("the native titlebar has no extra toolbar", panel.toolbar == nil)
        check("canvas gestures cannot drag the window", !panel.isMovableByWindowBackground)
        check("canvas is below the native titlebar", !panel.styleMask.contains(.fullSizeContentView))
        let clean = try await editor.webView.evaluateJavaScript("""
        !document.querySelector('.welcome-screen-center') &&
        !document.body.textContent.includes('Try Excalidraw+') &&
        !document.body.textContent.includes('Sign up')
        """) as? Bool == true
        check("the editor starts without welcome branding or promotions", clean)
        let localFont = try await editor.webView.callAsyncJavaScript("""
        const font = await fetch(new URL('fonts/Assistant/Assistant-Regular.woff2', window.EXCALIDRAW_ASSET_PATH));
        return font.ok && (await font.arrayBuffer()).byteLength > 0;
        """, arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        check("font bytes are available locally for text export", localFont)
        try await holdForInspection()
        panel.appearance = NSAppearance(named: .darkAqua)
        try await verifyTheme(editor, expected: "dark")
        try await holdForInspection()
        panel.appearance = NSAppearance(named: .aqua)
        try await verifyTheme(editor, expected: "light")
        let blank = try await editor.webView.evaluateJavaScript("document.querySelector('canvas').toDataURL()") as? String
        _ = try await editor.webView.callAsyncJavaScript("""
        await window.oncastEditor.flush();
        const scene = JSON.stringify({
          type: 'excalidraw', version: 2, source: 'Oncast verification',
          elements: [{type:'rectangle', id:'oncast-test-rectangle', x:350, y:250, width:200, height:120,
            strokeColor:'#1e1e1e', backgroundColor:'#99e9f2', fillStyle:'solid', strokeWidth:2,
            roughness:1, opacity:100, angle:0, version:1, versionNonce:1, isDeleted:false,
            groupIds:[], seed:1, updated:1, frameId:null, boundElements:null, link:null, locked:false}],
          appState: {viewBackgroundColor:'#ffffff', scrollX:0, scrollY:0}, files:{}
        });
        await new Promise((resolve, reject) => {
          const request = indexedDB.open('oncast-excalidraw', 1);
          request.onerror = () => reject(request.error);
          request.onsuccess = () => {
            const db = request.result;
            const tx = db.transaction('editor', 'readwrite');
            tx.objectStore('editor').put(scene, 'scene');
            tx.oncomplete = () => { db.close(); resolve(); };
            tx.onerror = () => reject(tx.error);
          };
        });
        """, arguments: [:], in: nil, contentWorld: .page)
        editor.reload()
        guard try await ready(editor) else { return }
        let restored = try await editor.webView.evaluateJavaScript("document.querySelector('canvas').toDataURL()") as? String
        check("a saved drawing renders after Reload", blank != restored)
        _ = try await editor.webView.callAsyncJavaScript(
            "await window.oncastEditor.flush();", arguments: [:], in: nil, contentWorld: .page)
    }

    static func reopen(identifier: UUID) async throws {
        let (editor, panel) = open(identifier: identifier)
        defer { panel.contentViewController = nil; panel.close() }
        guard try await ready(editor) else { return }
        let persisted = try await editor.webView.callAsyncJavaScript("""
        return await new Promise((resolve, reject) => {
          const request = indexedDB.open('oncast-excalidraw', 1);
          request.onerror = () => reject(request.error);
          request.onsuccess = () => {
            const db = request.result;
            const get = db.transaction('editor').objectStore('editor').get('scene');
            get.onsuccess = () => {
              db.close();
              resolve(JSON.parse(get.result).elements.some(e => e.id === 'oncast-test-rectangle'));
            };
            get.onerror = () => reject(get.error);
          };
        });
        """, arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        check("closing and reopening the window retains the drawing", persisted)
    }

    static func ready(_ editor: ExcalidrawViewController) async throws -> Bool {
        for _ in 0..<300 {
            if !editor.webView.isLoading, !editor.webView.isHidden {
                let rendered = try await editor.webView.evaluateJavaScript(
                    "document.querySelector('.excalidraw canvas')?.getBoundingClientRect().width > 0") as? Bool == true
                if rendered {
                    try await Task.sleep(for: .milliseconds(150))
                    return true
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        check("the embedded editor finishes loading", false)
        return false
    }

    static func verifyTheme(_ editor: ExcalidrawViewController, expected: String) async throws {
        for _ in 0..<30 {
            let theme = try await editor.webView.evaluateJavaScript("document.documentElement.dataset.theme") as? String
            if theme == expected {
                check("editor follows the window's \(expected) appearance", true)
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        check("editor follows the window's \(expected) appearance", false)
    }

    static func holdForInspection() async throws {
        if let seconds = ProcessInfo.processInfo.environment["ONCAST_TEST_EXCALIDRAW_HOLD_SECONDS"].flatMap(Double.init) {
            try await Task.sleep(for: .seconds(seconds))
        }
    }
}

enum Theme {
    enum Spacing { static let md: CGFloat = 8 }
    enum Colors {
        static let excalidrawCanvas = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1) : .white
        })
    }
}
