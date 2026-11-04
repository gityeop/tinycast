import Foundation
import Network
import OSLog

@MainActor
final class MCPSetupToolServer {
    typealias Invoke = @MainActor @Sendable (AIToolCall) async -> AIToolResult
    private let token = UUID().uuidString
    private var listener: NWListener?
    private var startup: Task<UInt16, Error>?
    private var ready: CheckedContinuation<UInt16, Error>?
    private var handlers: [UUID: Invoke] = [:]
    private var work: [UUID: Task<Void, Never>] = [:]
    private var connections: [UUID: NWConnection] = [:]

    func server(for chat: UUID, invoke: @escaping Invoke) async throws -> AIToolServer {
        handlers[chat] = invoke
        let port: UInt16
        if let current = listener?.port { port = current.rawValue } else if let startup {
            port = try await startup.value
        } else {
            let task = Task { try await start() }
            startup = task
            defer { startup = nil }
            port = try await task.value
        }
        return AIToolServer(handle: MCPSetupTools.handle, title: "Oncast Setup",
            transport: .url("http://127.0.0.1:\(port)/mcp",
                            headerName: "Authorization", headerValue: "Bearer \(token)"))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for task in work.values { task.cancel() }
        for connection in connections.values { connection.cancel() }
        handlers = [:]
        work = [:]
        connections = [:]
    }

    private func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        return try await withCheckedThrowingContinuation { reply in
            ready = reply
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, let reply = self.ready else { return }
                    switch state {
                    case .ready:
                        guard let port = self.listener?.port else { return }
                        self.ready = nil
                        reply.resume(returning: port.rawValue)
                    case .failed(let error):
                        self.ready = nil
                        reply.resume(throwing: error)
                    case .cancelled:
                        self.ready = nil
                        reply.resume(throwing: CancellationError())
                    default: break
                    }
                }
            }
            listener.start(queue: .global())
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task { @MainActor in
                    self?.work.removeValue(forKey: id)?.cancel()
                    self?.connections[id] = nil
                }
            }
        }
        connection.start(queue: .global())
        receive(connection, id: id, data: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] bytes, _, ended, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var buffer = data
                if let bytes { buffer.append(bytes) }
                if error != nil { connection.cancel(); return }
                guard buffer.count <= 1_048_576 else { self.respond(connection, status: 413); return }
                guard let boundary = buffer.range(of: Data("\r\n\r\n".utf8)),
                    let header = String(data: buffer[..<boundary.lowerBound], encoding: .utf8) else {
                    if ended { connection.cancel() } else { self.receive(connection, id: id, data: buffer) }
                    return
                }
                let lines = header.components(separatedBy: "\r\n")
                let request = lines[0].split(separator: " ")
                let fields = lines.dropFirst().compactMap { line -> (String, String)? in
                    guard let colon = line.firstIndex(of: ":") else { return nil }
                    return (line[..<colon].lowercased(), line[line.index(after: colon)...]
                        .trimmingCharacters(in: .whitespaces))
                }
                let headers = Dictionary(fields, uniquingKeysWith: { first, _ in first })
                guard headers["authorization"] == "Bearer \(self.token)" else {
                    self.respond(connection, status: 401); return
                }
                guard request.count >= 2, request[0] == "POST" else {
                    self.respond(connection, status: 405); return
                }
                guard request[1] == "/mcp", let length = headers["content-length"].flatMap(Int.init), length >= 0 else {
                    self.respond(connection, status: 400); return
                }
                let body = buffer[boundary.upperBound...]
                guard body.count >= length else {
                    if ended { connection.cancel() } else { self.receive(connection, id: id, data: buffer) }
                    return
                }
                self.work[id] = Task {
                    do {
                        let rpc = try JSONSerialization.jsonObject(with: Data(body.prefix(length))) as? [String: Any]
                        guard let rpc, let method = rpc["method"] as? String else {
                            self.respond(connection, status: 400); return
                        }
                        guard let rpcID = rpc["id"] else { self.respond(connection, status: 202); return }
                        let params = rpc["params"] as? [String: Any] ?? [:]
                        let result: [String: Any]
                        switch method {
                        case "initialize":
                            result = ["protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                                      "capabilities": ["tools": [:]],
                                      "serverInfo": ["name": "Oncast Setup", "version": "1.0"]]
                        case "tools/list":
                            result = ["tools": MCPSetupTools.tools.map {
                                ["name": $0.name, "description": $0.description, "inputSchema": $0.parameters.jsonObject]
                            }]
                        case "tools/call":
                            guard let name = params["name"] as? String else {
                                self.respond(connection, status: 400); return
                            }
                            guard let input = params["arguments"] as? [String: Any],
                                let chatID = input["conversation_id"] as? String, let chat = UUID(uuidString: chatID),
                                let invoke = self.handlers[chat] else {
                                self.respond(connection, status: 400); return
                            }
                            let arguments = try JSONSerialization.data(withJSONObject: input)
                            guard let argumentText = String(data: arguments, encoding: .utf8) else {
                                throw AIProviderError.malformedResponse
                            }
                            let value = await invoke(AIToolCall(id: UUID().uuidString, name: name, arguments: argumentText))
                            result = ["content": [["type": "text", "text": value.content]], "isError": value.isError]
                        case "ping": result = [:]
                        default:
                            self.respond(connection, status: 200, json: ["jsonrpc": "2.0", "id": rpcID,
                                "error": ["code": -32601, "message": "Unknown MCP method"]])
                            return
                        }
                        try Task.checkCancellation()
                        self.respond(connection, status: 200, json: ["jsonrpc": "2.0", "id": rpcID, "result": result])
                    } catch {
                        Logger(subsystem: "com.gityeop.tinycast", category: "MCPSetup")
                            .error("Setup tool transport failed: \(error.localizedDescription, privacy: .private)")
                        self.respond(connection, status: 500)
                    }
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, status: Int, json: [String: Any]? = nil) {
        do {
            let body = try json.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
            let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Response")\r\n"
                + "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            var response = Data(header.utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        } catch { connection.cancel() }
    }
}
