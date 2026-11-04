import Foundation
import Network
import OSLog

@MainActor
final class CanvasSocketServer {
    private let socketURL: URL
    private let handle: (CanvasRequest) async throws -> String
    private let report: (Error) -> Void
    private var task: Task<Void, Never>?
    private var ownsSocket = false
    private static let logger = Logger(subsystem: CanvasEndpoint.bundleID, category: "CanvasMCP")

    init(
        socketURL: URL = CanvasEndpoint.socketURL,
        handle: @escaping (CanvasRequest) async throws -> String,
        report: @escaping (Error) -> Void
    ) {
        self.socketURL = socketURL
        self.handle = handle
        self.report = report
    }

    isolated deinit { stop() }

    func start() throws {
        guard task == nil else { return }
        guard !FileManager.default.fileExists(atPath: socketURL.path) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE), userInfo: [
                NSLocalizedDescriptionKey: "Canvas MCP socket already exists: \(socketURL.path). Close the other Oncast instance."
            ])
        }
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let listener = try NetworkListener(using: .parameters { TCP() }.localEndpoint(.unix(path: socketURL.path)))
        task = Task { [weak self] in
            do {
                try await listener.onStateUpdate { [weak self] _, state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        ownsSocket = true
                        do {
                            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: socketURL.path)
                        } catch { report(error); stop() }
                    case .waiting(let error), .failed(let error):
                        report(error)
                        stop()
                    default: break
                    }
                }.run { [weak self] connection in await self?.receive(connection) }
            } catch is CancellationError {
                return
            } catch { self?.report(error) }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        guard ownsSocket else { return }
        ownsSocket = false
        do {
            try FileManager.default.removeItem(at: socketURL)
        } catch { Self.logger.error("Socket removal failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func receive(_ connection: NetworkConnection<TCP>) async {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in try await self?.respond(connection) }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw URLError(.timedOut)
                }
                defer { group.cancelAll() }
                _ = try await group.next()
            }
        } catch {
            Self.logger.error("Canvas request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func respond(_ connection: NetworkConnection<TCP>) async throws {
        var bytes = Data()
        while !bytes.contains(10) {
            guard bytes.count < 16 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            let message = try await connection.receive(atLeast: 1, atMost: 65536)
            bytes.append(message.content)
            if message.metadata.endOfStream, !bytes.contains(10) { throw URLError(.networkConnectionLost) }
        }
        let reply: CanvasReply
        do {
            let data = Data(bytes.prefix { $0 != 10 })
            let request = try await Task.detached { try JSONDecoder().decode(CanvasRequest.self, from: data) }.value
            reply = .result(try await handle(request))
        } catch {
            reply = .error(error.localizedDescription)
        }
        var data = try await Task.detached { try JSONEncoder().encode(reply) }.value
        data.append(10)
        try await connection.send(data, endOfStream: true)
    }
}
