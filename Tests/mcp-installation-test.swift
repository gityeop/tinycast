import Darwin
import Foundation

@main
@MainActor
struct MCPInstallationTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ value: Bool, _ message: String) {
        if value { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MCP install '\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try await aCompletePlanBuildsStartsTestsAndRestores(root)
        try await anHTTPServerUsesTheSamePlanRunner(root)
        try await failedStepsStopThePlan(root)
        try await cancellationStopsTheCommandTree(root)
        try await blockedPlansHaveNoEffects(root)
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func step(
        _ title: String, _ command: String, _ arguments: [String], directory: String = ".",
        kind: MCPInstallPlan.Step.Kind = .command, port: Int = 0
    ) -> MCPInstallPlan.Step {
        .init(title: title, kind: kind, command: command, arguments: arguments,
              directory: directory, readyPort: port, evidence: title)
    }

    static func freePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw AIProviderError.responseFailed("Test socket failed") }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw AIProviderError.responseFailed("Test bind failed") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    static func waitUntil(_ condition: () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(4)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    static func aCompletePlanBuildsStartsTestsAndRestores(_ root: URL) async throws {
        let manager = MCPInstallationManager(root: root)
        defer { manager.stopAll() }
        let port = try freePort()
        let stub = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Tests/ai-fixtures/mcp-stub.js").path
        let original = MCPServer(name: "Generic local fixture", transport: .stdio(
            command: "npm", arguments: ["--silent", "start"], environmentKeys: ["TEST_TOKEN"]))
        let buildSource = """
            const fs=require('fs'); if(!process.env.TEST_TOKEN)process.exit(9);
            if(require('fixture-dependency')!==42)process.exit(10);
            fs.writeFileSync('built.txt',process.cwd());
            const count=fs.existsSync('build-count')?Number(fs.readFileSync('build-count','utf8')):0;
            fs.writeFileSync('build-count',String(count+1));
            """
        let buildLiteral = String(bytes: try JSONEncoder().encode(buildSource), encoding: .utf8)!
        let stubLiteral = String(bytes: try JSONEncoder().encode(stub), encoding: .utf8)!
        let plan = MCPInstallPlan(directory: "server", steps: [
            step("Create trusted local source", "node", ["-e", """
                const fs=require('fs'); fs.mkdirSync('seed/fixture-dependency',{recursive:true});
                fs.writeFileSync('seed/fixture-dependency/package.json',JSON.stringify({
                  name:'fixture-dependency',version:'1.0.0',main:'index.cjs'}));
                fs.writeFileSync('seed/fixture-dependency/index.cjs','module.exports=42;');
                fs.writeFileSync('seed/build.cjs',\(buildLiteral));
                fs.writeFileSync('seed/package.json',JSON.stringify({name:'fixture-mcp',version:'1.0.0',private:true,
                  scripts:{build:'node build.cjs',start:'node '+JSON.stringify(\(stubLiteral))},
                  dependencies:{'fixture-dependency':'file:./fixture-dependency'}}));
                """]),
            step("Initialize fixture repository", "git", ["-c", "core.hooksPath=/dev/null", "init", "-q", "seed"]),
            step("Stage source", "git", ["-C", "seed", "-c", "core.hooksPath=/dev/null", "add", "."]),
            step("Commit fixture source", "git", ["-C", "seed", "-c", "core.hooksPath=/dev/null",
                 "-c", "user.name=MCP Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"]),
            step("Clone repository", "git", ["-c", "core.hooksPath=/dev/null", "clone", "--quiet", "seed", "server"]),
            step("Install dependencies", "npm", ["install", "--offline", "--ignore-scripts", "--no-audit", "--no-fund",
                 "--cache", "{install}/cache"], directory: "server"),
            step("Build project", "npm", ["run", "build", "--silent"], directory: "server"),
            step("Start bridge", "node", ["-e", """
                require('net').createServer(s=>s.end()).listen(\(port),'127.0.0.1');
                """], directory: "server", kind: .service, port: port)
        ], blockers: [])
        let installRoot = manager.directory(for: original.id)
        expect(!FileManager.default.fileExists(atPath: installRoot.path), "planning has no installation side effects")
        let environment = ["TEST_TOKEN": "fixture-secret"]
        let configured = try await manager.prepare(plan, server: original, environment: environment)
        expect(FileManager.default.fileExists(atPath: installRoot.appending(
            path: "server/node_modules/fixture-dependency/package.json").path), "the plan performs a real offline npm install")
        let actualDirectory = try String(contentsOf: installRoot.appending(path: "server/built.txt"), encoding: .utf8)
        let actualID = try FileManager.default.attributesOfItem(atPath: actualDirectory)[.systemFileNumber] as? NSNumber
        let expectedAttributes = try FileManager.default.attributesOfItem(atPath: installRoot.appending(path: "server").path)
        let expectedID = expectedAttributes[.systemFileNumber] as? NSNumber
        expect(actualID != nil && actualID == expectedID,
               "the build runs in its planned folder, including spaces and quotes")
        expect(await MCPServiceReadiness.isListening(port: port), "the bridge is ready before the MCP test")
        let connection = MCPServerConnection(server: configured, secrets: .init(environment: environment))
        await connection.start()
        expect(connection.status == .ready(tools: 2), "the installed launcher's real MCP handshake lists tools")
        connection.stop()
        let suite = "oncast-mcp-install-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = MCPSettingsStore(defaults: defaults)
        expect(registry.servers.isEmpty, "installation and testing do not register a server early")
        try manager.commit(plan, server: configured)
        registry.save(configured)
        expect(registry.server(id: configured.id)?.transport == configured.transport,
               "only the verified launcher is registered")
        let saved = try String(contentsOf: installRoot.appending(path: "installation.json"), encoding: .utf8)
        expect(!saved.contains("fixture-secret"), "approved installation metadata stores no environment values")
        manager.stopAll()
        expect(try await waitUntil { !(await MCPServiceReadiness.isListening(port: port)) }, "disabling MCP stops its bridge")

        let restored = MCPInstallationManager(root: root)
        defer { restored.stopAll() }
        try await restored.ensureServices(for: configured, environment: environment)
        try await restored.ensureServices(for: configured, environment: environment)
        expect(await MCPServiceReadiness.isListening(port: port), "restart restores the approved bridge exactly once")
        expect(try String(contentsOf: installRoot.appending(path: "server/build-count"), encoding: .utf8)
            == "1", "restart does not rerun checkout or build steps")
        restored.retain([])
        expect(try await waitUntil { !(await MCPServiceReadiness.isListening(port: port)) }, "removing a server stops its bridge")
    }

    static func failedStepsStopThePlan(_ root: URL) async throws {
        let manager = MCPInstallationManager(root: root)
        defer { manager.stopAll() }
        let server = MCPServer(name: "Broken build")
        let plan = MCPInstallPlan(directory: ".", steps: [
            step("Failing build", "/bin/sh", ["-c", "echo expected-fixture-error >&2; exit 7"]),
            step("Must not run", "/usr/bin/touch", ["unreachable"])
        ], blockers: [])
        do {
            _ = try await manager.prepare(plan, server: server, environment: [:])
            expect(false, "a failed build must fail setup")
        } catch { expect(error.localizedDescription.contains("Failing build"), "failure names the step that stopped") }
        expect(!FileManager.default.fileExists(atPath: manager.directory(for: server.id).appending(path: "unreachable").path),
               "later steps are never executed after a failure")
        let record = manager.directory(for: server.id).appending(path: "installation.json")
        expect(!FileManager.default.fileExists(atPath: record.path),
               "failed preparation is not committed as an installed MCP")
    }

    static func anHTTPServerUsesTheSamePlanRunner(_ root: URL) async throws {
        let manager = MCPInstallationManager(root: root)
        defer { manager.stopAll() }
        let port = try freePort()
        let script = """
            require('http').createServer(async(req,res)=>{
              let body=''; for await(const part of req)body+=part;
              const q=JSON.parse(body); if(q.id===undefined){res.writeHead(202);res.end();return;}
              const result=q.method==='initialize'?{protocolVersion:'2025-06-18',capabilities:{tools:{}}}
                :{tools:[{name:'health',description:'Fixture health',inputSchema:{type:'object',properties:{}}}]};
              res.writeHead(200,{'Content-Type':'application/json'});
              res.end(JSON.stringify({jsonrpc:'2.0',id:q.id,result}));
            }).listen(\(port),'127.0.0.1');
            """
        let server = MCPServer(name: "Independent HTTP fixture", transport: .http(
            url: "http://127.0.0.1:\(port)/mcp", headerName: ""))
        let plan = MCPInstallPlan(directory: ".", steps: [
            step("Start HTTP MCP", "node", ["-e", script], kind: .service, port: port)
        ], blockers: [])
        let configured = try await manager.prepare(plan, server: server, environment: [:])
        let connection = MCPServerConnection(server: configured, secrets: .init())
        await connection.start()
        expect(connection.status == .ready(tools: 1), "a different HTTP MCP uses the same install, readiness and handshake flow")
        connection.stop()
        try manager.commit(plan, server: configured)

        let competing = MCPServer(name: "Conflicting service")
        do {
            _ = try await manager.prepare(plan, server: competing, environment: [:])
            expect(false, "an occupied port must stop setup")
        } catch { expect(error.localizedDescription.contains("already in use"), "port conflicts are explained") }
        expect(await MCPServiceReadiness.isListening(port: port), "a port conflict never kills or replaces the existing process")
    }

    static func cancellationStopsTheCommandTree(_ root: URL) async throws {
        let manager = MCPInstallationManager(root: root)
        defer { manager.stopAll() }
        let server = MCPServer(name: "Cancelled build")
        let plan = MCPInstallPlan(directory: ".", steps: [
            step("Waiting build", "node", ["-e", """
                const child=require('child_process').spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'inherit'});
                require('fs').writeFileSync('child-pid',String(child.pid)); setInterval(()=>{},1000);
                """]),
            step("Must not run", "/usr/bin/touch", ["unreachable"])
        ], blockers: [])
        let task = Task { try await manager.prepare(plan, server: server, environment: [:]) }
        let childFile = manager.directory(for: server.id).appending(path: "child-pid")
        expect(try await waitUntil { FileManager.default.fileExists(atPath: childFile.path) },
               "the build started before cancellation")
        let pid = Int32(try String(contentsOf: childFile, encoding: .utf8))!
        task.cancel()
        do { _ = try await task.value; expect(false, "a cancelled setup must not succeed") } catch {
            expect(error is CancellationError, "Stop cancels the setup operation")
        }
        expect(try await waitUntil { kill(pid, 0) != 0 }, "Stop kills the build's child process too")
    }

    static func blockedPlansHaveNoEffects(_ root: URL) async throws {
        let manager = MCPInstallationManager(root: root)
        let server = MCPServer(name: "Missing source")
        let plan = MCPInstallPlan(directory: ".", steps: [], blockers: ["Required bridge source is not published."])
        do {
            _ = try await manager.prepare(plan, server: server, environment: [:])
            expect(false, "blocked setup must fail")
        } catch { expect(error.localizedDescription.contains("source"), "the missing prerequisite is explained") }
        expect(!FileManager.default.fileExists(atPath: manager.directory(for: server.id).path),
               "a blocked plan creates no installation folder or processes")
    }
}
