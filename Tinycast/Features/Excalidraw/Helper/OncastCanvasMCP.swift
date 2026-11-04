import CoreFoundation
import Foundation

@main
struct OncastCanvasMCP {
    static let handshakeVersion = "2025-11-25"
    static let modernVersion = "2026-07-28"
    static let info = ["name": "oncast-canvas", "version": "1.0.0"]
    static let instructions = """
    Work on the canvas currently open in Oncast. Read it first. Mutations must carry the returned
    canvasId and revision. On a conflict, read again and reconsider the change; do not overwrite it.
    Creates accept Excalidraw skeletons, including text labels and arrow endpoints. Updates target
    element IDs. Geometry updates to connected shapes should include their arrow geometry.
    Example create: {"type":"rectangle","id":"box","x":100,"y":100,"width":180,"height":90,"label":{"text":"Start"}}.
    For label edits, update the text element ID returned by read_canvas, not the container ID.
    This server exposes only the canvas, not other Oncast features or arbitrary code execution.
    """

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let socket: URL
        if arguments.isEmpty {
            socket = CanvasEndpoint.socketURL
        } else if arguments.count == 2, arguments[0] == "--socket" {
            socket = URL(filePath: arguments[1])
        } else {
            FileHandle.standardError.write(Data("Usage: OncastCanvasMCP [--socket PATH]\n".utf8))
            exit(2)
        }
        var initialized = false
        while let line = readLine() {
            guard !line.isEmpty else { continue }
            let response = process(line, socket: socket, initialized: &initialized)
            guard let response else { continue }
            do {
                var bytes = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
                bytes.append(10)
                try FileHandle.standardOutput.write(contentsOf: bytes)
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    static func process(_ line: String, socket: URL, initialized: inout Bool) -> [String: Any]? {
        var id: Any = NSNull()
        do {
            guard let message = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String
            else { return error(id: id, code: -32600, message: "Invalid JSON-RPC request") }
            guard let requestID = message["id"] else { return nil }
            guard requestID is String || (requestID as? NSNumber).map({ CFGetTypeID($0) != CFBooleanGetTypeID() }) == true else {
                return error(id: id, code: -32600, message: "A request ID must be a string or number")
            }
            id = requestID
            let params: [String: Any]
            switch message["params"] {
            case nil: params = [:]
            case let object as [String: Any]: params = object
            default: return error(id: id, code: -32602, message: "params must be an object")
            }
            let metadata: [String: Any]?
            switch params["_meta"] {
            case nil: metadata = nil
            case let object as [String: Any]: metadata = object
            default: return error(id: id, code: -32602, message: "_meta must be an object")
            }
            let version: String?
            switch metadata?["io.modelcontextprotocol/protocolVersion"] {
            case nil: version = nil
            case let string as String: version = string
            default: return error(id: id, code: -32602, message: "protocolVersion must be a string")
            }
            let modern = version != nil
            if let version, version != modernVersion {
                return error(id: id, code: -32022, message: "Unsupported protocol version", data: [
                    "requested": version, "supported": [modernVersion, handshakeVersion]
                ])
            }
            if modern {
                guard let client = metadata?["io.modelcontextprotocol/clientInfo"] as? [String: Any],
                    client["name"] is String, client["version"] is String,
                    metadata?["io.modelcontextprotocol/clientCapabilities"] is [String: Any]
                else {
                    return error(id: id, code: -32602, message: "Modern MCP requests require clientInfo and clientCapabilities")
                }
            }
            if method == "initialize", !modern {
                guard params["protocolVersion"] is String else {
                    return error(id: id, code: -32602, message: "protocolVersion is required")
                }
                initialized = true
                return result(id: id, body: [
                    "protocolVersion": handshakeVersion, "serverInfo": info,
                    "capabilities": ["tools": [:]], "instructions": instructions
                ])
            }
            if method == "server/discover" {
                return result(id: id, body: [
                    "resultType": "complete", "supportedVersions": [modernVersion, handshakeVersion],
                    "capabilities": ["tools": [:]], "instructions": instructions,
                    "_meta": ["io.modelcontextprotocol/serverInfo": info]
                ])
            }
            guard modern || initialized else {
                return error(id: id, code: -32600, message: "Initialize the MCP connection before calling tools")
            }
            var body: [String: Any]
            switch method {
            case "ping": body = [:]
            case "tools/list": body = ["tools": tools]
            case "tools/call":
                guard let name = params["name"] as? String, let operation = CanvasOperation(rawValue: name) else {
                    return error(id: id, code: -32602, message: "Unknown canvas tool")
                }
                let arguments = params["arguments"] ?? [String: Any]()
                guard arguments is [String: Any] else {
                    return error(id: id, code: -32602, message: "Tool arguments must be an object")
                }
                do {
                    let reply = try CanvasSocketClient.call(
                        CanvasRequest(operation: operation, arguments: try jsonString(arguments)), socketURL: socket)
                    switch reply {
                    case .error(let message): body = toolError(message)
                    case .result(let json):
                        guard let payload = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
                            throw NSError(domain: "CanvasMCP", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: "Oncast returned an invalid canvas response"
                            ])
                        }
                        if operation == .snapshot {
                            guard let image = payload["image"] as? String else { throw URLError(.cannotParseResponse) }
                            let metadata = payload.filter { $0.key != "image" }
                            let text = try jsonString(metadata)
                            body = ["content": [["type": "text", "text": text],
                                                ["type": "image", "mimeType": "image/png", "data": image]]]
                        } else {
                            body = ["content": [["type": "text", "text": json]], "structuredContent": payload]
                        }
                    }
                } catch { body = toolError(error.localizedDescription) }
            default: return error(id: id, code: -32601, message: "Unknown MCP method: \(method)")
            }
            if modern { body["resultType"] = "complete" }
            return result(id: id, body: body)
        } catch { return self.error(id: id, code: -32700, message: error.localizedDescription) }
    }

    static func result(id: Any, body: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": body]
    }

    static func error(id: Any, code: Int, message: String, data: [String: Any]? = nil) -> [String: Any] {
        var details: [String: Any] = ["code": code, "message": message]
        if let data { details["data"] = data }
        return ["jsonrpc": "2.0", "id": id, "error": details]
    }

    static func toolError(_ message: String) -> [String: Any] {
        ["isError": true, "content": [["type": "text", "text": message]]]
    }

    static func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return text
    }

    static var tools: [[String: Any]] {
        let empty: [String: Any] = ["type": "object", "additionalProperties": false]
        let canvas: [String: Any] = [
            "type": "object", "required": ["canvasId"], "additionalProperties": false,
            "properties": ["canvasId": ["type": "string"]]
        ]
        let changes: [String: Any] = [
            "type": "object", "required": ["canvasId", "expectedRevision"], "additionalProperties": false,
            "properties": [
                "canvasId": ["type": "string"], "expectedRevision": ["type": "integer", "minimum": 0],
                "create": ["type": "array", "items": ["type": "object", "required": ["type", "x", "y"], "properties": [
                    "type": ["type": "string", "enum": ["rectangle", "ellipse", "diamond", "text", "arrow", "line"]],
                    "id": ["type": "string"], "x": ["type": "number"], "y": ["type": "number"],
                    "width": ["type": "number"], "height": ["type": "number"], "text": ["type": "string"],
                    "label": ["type": "object", "properties": ["text": ["type": "string"]]],
                    "start": ["type": "object", "properties": ["id": ["type": "string"]]],
                    "end": ["type": "object", "properties": ["id": ["type": "string"]]]
                ]]],
                "update": ["type": "array", "items": ["type": "object", "required": ["id", "changes"],
                    "additionalProperties": false, "properties": [
                        "id": ["type": "string"], "changes": ["type": "object"]
                    ]]],
                "delete": ["type": "array", "items": ["type": "string"]]
            ]
        ]
        return [
            tool(.readCanvas, "Read the current drawing, selection and revision. Call before editing.", empty, readOnly: true),
            tool(.applyChanges, "Atomically edit elements using the canvasId and revision from read_canvas.",
                 changes, readOnly: false),
            tool(.exportScene, "Export portable Excalidraw JSON with attached files.", canvas, readOnly: true),
            tool(.snapshot, "Render a PNG of the current drawing for visual inspection.", canvas, readOnly: true)
        ]
    }

    static func tool(
        _ operation: CanvasOperation, _ description: String, _ schema: [String: Any], readOnly: Bool
    ) -> [String: Any] {
        ["name": operation.rawValue, "description": description, "inputSchema": schema,
         "annotations": ["readOnlyHint": readOnly, "destructiveHint": !readOnly, "openWorldHint": false]]
    }
}
