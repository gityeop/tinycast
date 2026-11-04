import Foundation
import Observation

@main
@MainActor
struct CanvasMCPClientTests {
    static func main() async throws {
        let helper = CommandLine.arguments[1]
        let socket = CommandLine.arguments[2]
        let suite = "canvas-client-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var canvas = CanvasMCPServer.make(helperURL: URL(filePath: helper))
        canvas.transport = .stdio(command: helper, arguments: ["--socket", socket], environmentKeys: [])
        let store = MCPSettingsStore(defaults: defaults, builtInServer: canvas)
        store.save(MCPServer(name: "External", transport: .stdio(
            command: "/must-not-run", arguments: [], environmentKeys: [])))
        let settings = AppSettings()
        let core = AppCore()
        let secrets = MCPSecretStore(keychain: KeychainSecretStore(scope: suite))
        let manager = MCPServerManager(secrets: secrets)
        defer { manager.stop() }
        let coordinator = MCPCoordinator(settings: settings, store: store, manager: manager, core: core)
        coordinator.applyEnabled()
        for _ in 0..<200 {
            if manager.status(of: canvas.id).isReady { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        precondition(manager.status(of: canvas.id) == .ready(tools: 4))
        precondition(manager.connections.count == 1)
        precondition(coordinator.servers.map(\.id) == [canvas.id])
        precondition(!settings.mcpEnabled)
        print("PASS: Oncast's native MCP client auto-connects only its built-in canvas while external MCP is off")

        let chat = UUID()
        let before = await read(coordinator, chat: chat)
        let provider = AIToolLoopProvider(
            base: CanvasScriptedProvider(), tools: coordinator.tools(scopedTo: nil), maxRounds: 8
        ) { call in await coordinator.invoke(call, in: chat) }
        var calls = 0
        var answer = ""
        for try await event in provider.stream(AIRequest(messages: [
            AIMessage(role: .user, text: "Verify the open canvas with a temporary shape.")
        ])) {
            switch event {
            case .toolResult(_, let isError): precondition(!isError); calls += 1
            case .text(let text): answer += text
            default: break
            }
        }
        precondition(calls == 5 && answer == "Canvas verified")
        let after = await read(coordinator, chat: chat)
        precondition(before["elements"] != nil && before["elements"] == after["elements"])
        precondition(core.permissionQuestions.count == 1)
        precondition(core.permissionQuestions[0].contains("open canvas"))
        print("PASS: the Oncast AI tool loop reads, creates, updates and deletes on the real canvas with one chat consent")

        core.aiChatCoordinator.everyChatRunsItsOwnTools = true
        coordinator.applyEnabled()
        let cliServers = await coordinator.toolServers(scopedTo: nil)
        precondition(cliServers.count == 1 && cliServers[0].handle == canvas.slug)
        precondition(coordinator.statusLabel(for: canvas) == "Ready in chat")
        precondition(manager.connections.isEmpty)
        print("PASS: Codex and Claude routes receive the built-in server without a duplicate resident client")

        var disabled = store.server(id: canvas.id)!
        disabled.isEnabled = false
        store.save(disabled)
        coordinator.applyEnabled()
        precondition(coordinator.tools(scopedTo: nil).isEmpty)
        let disabledServers = await coordinator.toolServers(scopedTo: nil)
        precondition(disabledServers.isEmpty)
        disabled.isEnabled = true
        store.save(disabled)
        settings.aiEnabled = false
        coordinator.applyEnabled()
        precondition(coordinator.servers.isEmpty && manager.connections.isEmpty)
        print("PASS: disabling canvas access or AI withholds the built-in tools")
    }

    static func read(_ coordinator: MCPCoordinator, chat: UUID) async -> [String: JSONValue] {
        let result = await coordinator.invoke(AIToolCall(
            id: UUID().uuidString, name: "oncast-canvas__read_canvas", arguments: "{}"), in: chat)
        precondition(!result.isError, result.content)
        return JSONValue(data: Data(result.content.utf8))!.objectValue!
    }
}

private struct CanvasScriptedProvider: AIProvider {
    func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            do {
                let results = request.messages.compactMap(\.toolResult)
                precondition(results.allSatisfy { !$0.isError })
                let name: String
                let arguments: [String: Any]
                switch results.count {
                case 0:
                    name = "read_canvas"
                    arguments = [:]
                case 1:
                    let scene = scene(results[0])
                    name = "apply_canvas_changes"
                    arguments = ["canvasId": scene["canvasId"]!.jsonObject,
                        "expectedRevision": scene["revision"]!.jsonObject,
                        "create": [["id": "internal-ai-test", "type": "rectangle", "x": 800,
                            "y": 400, "width": 180, "height": 80, "label": ["text": "Oncast AI"]]]]
                case 2:
                    let created = scene(results[1])
                    let elements = created["elements"]!.arrayValue!.compactMap(\.objectValue)
                    let label = elements.first { $0["containerId"]?.stringValue == "internal-ai-test" }!
                    name = "apply_canvas_changes"
                    arguments = ["canvasId": created["canvasId"]!.jsonObject,
                        "expectedRevision": created["revision"]!.jsonObject,
                        "update": [["id": "internal-ai-test", "changes": ["backgroundColor": "#b2f2bb"]],
                            ["id": label["id"]!.jsonObject, "changes": ["text": "Internal AI verified"]]]]
                case 3:
                    let updated = scene(results[2])
                    let elements = updated["elements"]!.arrayValue!.compactMap(\.objectValue)
                    precondition(elements.contains { $0["text"]?.stringValue == "Internal AI verified" })
                    let created = scene(results[1])
                    name = "apply_canvas_changes"
                    arguments = ["canvasId": updated["canvasId"]!.jsonObject,
                        "expectedRevision": updated["revision"]!.jsonObject,
                        "delete": created["createdElementIds"]!.jsonObject]
                case 4:
                    name = "read_canvas"
                    arguments = [:]
                default:
                    continuation.yield(.text("Canvas verified"))
                    continuation.yield(.finished)
                    continuation.finish()
                    return
                }
                let data = try JSONSerialization.data(withJSONObject: arguments)
                continuation.yield(.toolCallRequested(AIToolCall(
                    id: "canvas-\(results.count)", name: "oncast-canvas__\(name)",
                    arguments: String(bytes: data, encoding: .utf8)!)))
                continuation.yield(.finished)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func scene(_ result: AIToolResult) -> [String: JSONValue] {
        JSONValue(data: Data(result.content.utf8))!.objectValue!
    }
}

@Observable
@MainActor
final class AppSettings {
    var aiEnabled = true
    var mcpEnabled = false
}

@MainActor
final class AppCore {
    let mcpOAuth = MCPOAuthManager()
    let chatGPTSubscription = CanvasSubscriptionProbe()
    let aiChatCoordinator = CanvasChatProbe()
    var permissionQuestions: [String] = []

    func choose(title: String, message: String, symbol: String, options: [DialogAction], defaultIndex: Int) async -> Int {
        permissionQuestions.append(message)
        return 1
    }
}

@MainActor
final class CanvasSubscriptionProbe {
    func dropWithdrawnServers(keeping: Set<String>) {}
}

@MainActor
final class CanvasChatProbe {
    var everyChatRunsItsOwnTools = false
}

struct DialogAction {
    enum Role { case cancel }
    let title: String
    var role: Role?
}
