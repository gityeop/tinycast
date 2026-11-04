import Foundation

enum CanvasOperation: String, Codable, Sendable {
    case readCanvas = "read_canvas"
    case applyChanges = "apply_canvas_changes"
    case exportScene = "export_canvas_scene"
    case snapshot = "snapshot_canvas"
}

struct CanvasRequest: Codable, Sendable {
    let operation: CanvasOperation
    let arguments: String
}

enum CanvasReply: Codable, Sendable {
    case result(String)
    case error(String)
}

enum CanvasEndpoint {
    static let bundleID = "com.gityeop.tinycast"

    static var socketURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID).appendingPathComponent("CanvasMCP/socket")
    }

    static func configuration(helperURL: URL) throws -> String {
        let configuration = ["mcpServers": ["oncast-canvas": ["command": helperURL.path]]]
        let data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return text
    }
}
