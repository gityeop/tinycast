import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class MCPInstallationManager {
    private let root: URL
    private(set) var progress: [UUID: String] = [:]
    private(set) var failures: [UUID: String] = [:]
    @ObservationIgnored private var services: [UUID: [MCPInstallProcess]] = [:]
    @ObservationIgnored private var commands: [UUID: MCPInstallProcess] = [:]
    @ObservationIgnored private var launching: [UUID: Task<Void, Error>] = [:]
    @ObservationIgnored private var generations: [UUID: UUID] = [:]

    init(root: URL) { self.root = root }

    func directory(for id: UUID) -> URL { root.appending(path: id.uuidString, directoryHint: .isDirectory) }

    func prepare(
        _ plan: MCPInstallPlan, server: MCPServer, environment: [String: String]
    ) async throws -> MCPServer {
        guard plan.blockers.isEmpty else {
            throw AIProviderError.responseFailed(plan.blockers.joined(separator: "\n"))
        }
        let folder = directory(for: server.id)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw AIProviderError.responseFailed(
                "This setup folder already exists. Start a new setup request for a fresh installation.")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let generation = UUID()
        generations[server.id] = generation
        do {
            for step in plan.steps {
                try check(server.id, generation: generation)
                progress[server.id] = step.title
                if step.kind == .service {
                    try await startService(step, id: server.id, generation: generation, folder: folder, environment: environment)
                } else {
                    let process = try await start(step, folder: folder, environment: environment)
                    commands[server.id] = process
                    let status = try await process.wait()
                    commands[server.id] = nil
                    guard status == 0 else { throw stepFailure(step, process: process, values: Array(environment.values)) }
                }
            }
            try check(server.id, generation: generation)
            var configured = server
            if case .stdio(let command, let arguments, let keys) = server.transport {
                let launcher = folder.appending(path: "launch-mcp.sh")
                let executable: String
                let resolved = MCPInstallPlan.resolve(command, root: folder)
                if resolved.contains("/") {
                    executable = resolved.hasPrefix("/") ? resolved
                        : MCPInstallPlan.folder(plan.directory, root: folder).appending(path: resolved).path
                } else {
                    guard let found = await ExecutableLocator.locate(resolved) else {
                        throw AIProviderError.responseFailed("The final MCP executable \(resolved) is not installed.")
                    }
                    executable = found.path
                }
                try check(server.id, generation: generation)
                try Data(plan.launcher(command: executable, arguments: arguments, root: folder).utf8).write(to: launcher)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
                configured.transport = .stdio(command: launcher.path, arguments: [], environmentKeys: keys)
            }
            return configured
        } catch {
            if generations[server.id] == generation { stop(server.id) }
            throw error
        }
    }

    func commit(_ plan: MCPInstallPlan, server: MCPServer) throws {
        let keys: [String]
        if case .stdio(_, _, let environmentKeys) = server.transport { keys = environmentKeys } else { keys = [] }
        let record = MCPInstallation(serverID: server.id, plan: plan, environmentKeys: keys)
        let file = directory(for: server.id).appending(path: "installation.json")
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        progress[server.id] = "Connected"
    }

    func ensureServices(for server: MCPServer, environment: [String: String]) async throws {
        if let failure = failures[server.id] { throw AIProviderError.responseFailed(failure) }
        if let task = launching[server.id] { return try await task.value }
        if let running = services[server.id] {
            guard running.allSatisfy({ $0.status == nil }) else {
                let message = "A required background service has stopped. Check MCP settings."
                failures[server.id] = message
                throw AIProviderError.responseFailed(message)
            }
            return
        }
        let file = directory(for: server.id).appending(path: "installation.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let record: MCPInstallation
        do {
            record = try JSONDecoder().decode(MCPInstallation.self, from: Data(contentsOf: file))
        } catch {
            failures[server.id] = "The approved installation record could not be read. Setup stopped."
            throw error
        }
        let folder = directory(for: server.id)
        let generation = UUID()
        generations[server.id] = generation
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            for step in record.plan.steps where step.kind == .service {
                try self.check(server.id, generation: generation)
                self.progress[server.id] = step.title
                try await self.startService(step, id: server.id, generation: generation, folder: folder, environment: environment)
            }
        }
        launching[server.id] = task
        defer { if generations[server.id] == generation { launching[server.id] = nil } }
        do {
            try await task.value
        } catch {
            if generations[server.id] == generation {
                stop(server.id)
                failures[server.id] = "A required service could not start. Check its runtime and local port."
            }
            throw error
        }
    }

    func retain(_ ids: Set<UUID>) {
        for id in Set(services.keys).union(commands.keys).union(launching.keys).union(generations.keys)
            where !ids.contains(id) { stop(id) }
    }

    func stop(_ id: UUID) {
        generations[id] = nil
        launching.removeValue(forKey: id)?.cancel()
        commands.removeValue(forKey: id)?.stop()
        for process in services.removeValue(forKey: id) ?? [] { process.stop() }
        progress[id] = nil
        failures[id] = nil
    }

    func stopAll() {
        retain([])
    }

    private func check(_ id: UUID, generation: UUID) throws {
        try Task.checkCancellation()
        guard generations[id] == generation else { throw CancellationError() }
    }

    private func start(
        _ step: MCPInstallPlan.Step, folder: URL, environment: [String: String]
    ) async throws -> MCPInstallProcess {
        try await MCPInstallProcess.start(
            command: MCPInstallPlan.resolve(step.command, root: folder),
            arguments: step.arguments.map { MCPInstallPlan.resolve($0, root: folder) },
            directory: MCPInstallPlan.folder(step.directory, root: folder), environment: environment)
    }

    private func startService(
        _ step: MCPInstallPlan.Step, id: UUID, generation: UUID, folder: URL, environment: [String: String]
    ) async throws {
        guard !(await MCPServiceReadiness.isListening(port: step.readyPort)) else {
            throw AIProviderError.responseFailed(
                "Port \(step.readyPort) is already in use. The existing process was left running.")
        }
        let process = try await start(step, folder: folder, environment: environment)
        do { try check(id, generation: generation) } catch { process.stop(); throw error }
        services[id, default: []].append(process)
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if process.status != nil { throw stepFailure(step, process: process, values: Array(environment.values)) }
            if await MCPServiceReadiness.isListening(port: step.readyPort) { return }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw AIProviderError.responseFailed("\(step.title) did not become ready on port \(step.readyPort). Setup stopped.")
    }

    private func stepFailure(
        _ step: MCPInstallPlan.Step, process: MCPInstallProcess, values: [String]
    ) -> AIProviderError {
        let details = process.diagnostics(redacting: values)
        Logger(subsystem: "com.gityeop.tinycast", category: "MCPInstallation")
            .error("Installation step failed: \(step.title, privacy: .public): \(details, privacy: .private)")
        return .responseFailed("\(step.title) failed. Setup stopped; detailed diagnostics are in Console.")
    }
}
