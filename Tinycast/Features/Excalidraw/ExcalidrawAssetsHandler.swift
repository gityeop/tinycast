import Foundation
import WebKit

@MainActor
final class ExcalidrawAssetsHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "oncast-editor-assets"
    private let directory: URL
    private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(directory: URL) { self.directory = directory.standardizedFileURL }

    isolated deinit {
        for request in requests.values { request.cancel() }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let file = directory.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(directory.path + "/"), file.pathExtension == "woff2" else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        let identifier = ObjectIdentifier(urlSchemeTask)
        requests[identifier] = Task { [weak self] in
            defer { self?.requests.removeValue(forKey: identifier) }
            do {
                let data = try await Task.detached { try Data(contentsOf: file) }.value
                guard !Task.isCancelled else { return }
                guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                    "Content-Type": "font/woff2", "Content-Length": String(data.count),
                    "Access-Control-Allow-Origin": "*"
                ]) else {
                    throw URLError(.badServerResponse)
                }
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled else { return }
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        requests.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}
