import Foundation

@main
struct MCPSetupTests {
    @MainActor static var passed = 0
    @MainActor static var failed = 0

    @MainActor static func expect(_ condition: Bool, _ message: String) {
        if condition { passed += 1 } else { failed += 1; print("FAIL: \(message)") }
    }

    static let source = URL(string: "https://github.com/example/calendar-mcp")!
    static let documentation = #"{"command":"npx","args":["-y","calendar-mcp"],"env":{"CALENDAR_TOKEN":"YOUR_TOKEN"}}"#
    static var loadedDocument: MCPDocumentation { MCPDocumentation(text: documentation, sources: [source]) }
    static let configuration = """
        {"name":"Calendar","url":"","command":"npx",
        "arguments":["-y","calendar-mcp"],"environmentKeys":["CALENDAR_TOKEN"],
        "authentication":"none","headerName":"","notes":"Enter the calendar token in the review form.",
        "installation":{"directory":".","steps":[],"blockers":[]}}
        """

    @MainActor static func main() async throws {
        expect(try MCPSetupLink.documentationURL(for: source).absoluteString
            == source.absoluteString, "GitHub root reads its rendered README without an API quota")
        let blob = URL(string: "https://github.com/example/server/blob/main/docs/setup.md")!
        expect(try MCPSetupLink.documentationURL(for: blob).absoluteString
            == "https://raw.githubusercontent.com/example/server/main/docs/setup.md", "README file paths are preserved")
        let html = "<script>bad()</script><pre>{&quot;command&quot;:&quot;npx&quot;}</pre>"
        expect(MCPSetupLink.readableText(html, isHTML: true) == #"{"command":"npx"}"#, "HTML code survives without scripts")
        let market = URL(string: "https://mcpmarket.com/ko/server/apple-calendar")!
        let repository = URL(string: "https://github.com/shadowfax92/apple-calendar-mcp")!
        let listing = """
            <script type="application/ld+json">{"@type":"SoftwareApplication","url":"\(repository)",
            "author":{"url":"https://github.com/shadowfax92"},
            "isRelatedTo":[{"url":"https://github.com/other/unrelated"}]}</script>
            <h1>Apple Calendar</h1><a href="\(repository)" title="GitHub"><svg></svg></a>
            """
        expect(try MCPSetupLink.declaredRepository(in: listing) == repository,
               "the server's declared repository is retained before script and HTML stripping")
        expect(MCPSetupLink.readableText(#"<a href="https://example.com/install">Setup guide</a>"#, isHTML: true)
            .contains("[Setup guide](https://example.com/install)"), "documentation link targets survive text extraction")
        let resolved = try await MCPDocumentationService.fetch(market) { address in
            if address == market { return try MCPDocumentationService.page(body: listing, isHTML: true, source: market) }
            guard address == repository else { throw AIProviderError.malformedResponse }
            return MCPDocumentationService.Page(text: documentation, repository: nil)
        }
        expect(resolved.sources == [market, repository], "both the listing and repository are retained for approval")
        expect(resolved.text.contains(documentation), "configuration extraction receives the linked README")
        do {
            _ = try await MCPDocumentationService.fetch(market) { address in
                if address == market { return try MCPDocumentationService.page(body: listing, isHTML: true, source: market) }
                throw URLError(.cannotConnectToHost)
            }
            expect(false, "a failed linked README must not be hidden")
        } catch { expect(true, "linked README failures propagate instead of using the incomplete listing") }
        let arguments = ["-y", "package", "/Users/Someone/My Files", "it's here", "", #"a"b"#, #"C:\path"#]
        expect(MCPCommandArguments.parse(MCPCommandArguments.text(arguments)) == arguments,
               "reviewing a command preserves argument boundaries, quotes, empty arguments and backslashes")

        let proposal = try MCPInstallProposal.parse(configuration, document: documentation)
        guard var plannedObject = try JSONSerialization.jsonObject(with: Data(configuration.utf8)) as? [String: Any] else {
            throw AIProviderError.malformedResponse
        }
        plannedObject["command"] = "npm"
        plannedObject["arguments"] = ["--silent", "start"]
        plannedObject["installation"] = [
            "directory": "server", "blockers": [],
            "steps": [["title": "Build project", "kind": "command", "command": "npm",
                       "arguments": ["run", "build"], "directory": "server", "readyPort": 0,
                       "evidence": "npm run build"]]
        ]
        let plannedJSON = String(bytes: try JSONSerialization.data(withJSONObject: plannedObject), encoding: .utf8)!
        let planned = try MCPInstallProposal.parse(plannedJSON, document: documentation + " npm run build; npm start")
        expect(planned.installation.steps.count == 1 && planned.installation.directory == "server",
               "a complete build plan permits a project-relative final MCP command")
        plannedObject["installation"] = ["directory": ".", "steps": [], "blockers": ["Bridge source missing"]]
        plannedObject["command"] = ""
        plannedObject["url"] = ""
        let blockedJSON = String(bytes: try JSONSerialization.data(withJSONObject: plannedObject), encoding: .utf8)!
        let blocked = try MCPInstallProposal.parse(blockedJSON, document: documentation)
        expect(blocked.installation.blockers == ["Bridge source missing"], "an incomplete plan reaches review as a blocked plan")
        let server = proposal.server()
        expect(server.trust == .ask, "proposals never grant automatic tool permission")
        expect(server.id != proposal.server().id, "a proposal cannot overwrite a saved server ID")
        expect(server.transport == .stdio(command: "npx", arguments: ["-y", "calendar-mcp"],
                                          environmentKeys: ["CALENDAR_TOKEN"]), "only environment names enter the proposal")
        do {
            _ = try MCPInstallProposal.parse(
                configuration.replacingOccurrences(of: "npx", with: "invented"), document: documentation)
            expect(false, "invented command must be rejected")
        } catch { expect(true, "invented command is rejected") }
        do {
            _ = try MCPInstallProposal.parse(configuration, document: "No setup instructions here")
            expect(false, "undocumented configuration must be rejected")
        } catch { expect(true, "undocumented configuration is rejected") }
        do {
            let localScript = configuration.replacingOccurrences(of: #""command":"npx""#, with: #""command":"npm""#)
                .replacingOccurrences(of: #""arguments":["-y","calendar-mcp"]"#, with: #""arguments":["start"]"#)
            _ = try MCPInstallProposal.parse(localScript, document: documentation + " npm start")
            expect(false, "a project-relative npm script must not run from the user's home directory")
        } catch { expect(true, "npm start requires the installed project's path") }
        do {
            _ = try MCPInstallProposal.parse(#"{"error":"No supported configuration documented"}"#, document: documentation)
            expect(false, "incomplete documentation must fail")
        } catch { expect(true, "incomplete documentation fails without guessing") }

        let httpJSON = """
            {"name":"Hosted Calendar","url":"https://calendar.example/mcp",
            "command":"","arguments":[],"environmentKeys":[],"authentication":"oauth",
            "headerName":"Authorization","notes":"Sign in after approval.",
            "installation":{"directory":".","steps":[],"blockers":[]}}
            """
        let hosted = try MCPInstallProposal.parse(httpJSON, document: "Connect to https://calendar.example/mcp using OAuth.")
        expect(hosted.server().oauth == true, "documented hosted OAuth servers retain their authentication mode")
        do {
            _ = try MCPInstallProposal.parse(httpJSON, document: "No hosted endpoint here.")
            expect(false, "an undocumented endpoint must fail")
        } catch { expect(true, "undocumented endpoints are rejected") }
        do {
            _ = try MCPInstallProposal.parse(
                httpJSON.replacingOccurrences(of: #""command":"""#, with: #""command":"npx""#),
                document: documentation + " https://calendar.example/mcp")
            expect(false, "conflicting transports must fail")
        } catch { expect(true, "conflicting transports are rejected rather than corrected") }

        try nativeOutcomesSurviveFailedReplies()
        try await nativeReceiptWaitsForTheStreamingReply()
        try await nativeToolsAreAvailableWithoutPhraseRouting()
        print("\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }

    @MainActor static func nativeOutcomesSurviveFailedReplies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatHistoryStore(directory: directory)
        var chat = ChatSession()
        chat.append(ChatMessage(role: .user, text: "MCP 설치 작업"))
        store.save(chat)
        let first = MCPSetupOutcome(source: source, name: "Calendar", state: .connected,
            serverID: UUID(), tools: 13, detail: "Connection test passed", recordedAt: Date())
        let second = MCPSetupOutcome(source: URL(string: "https://example.com/other-mcp")!, name: "Other", state: .failed,
            serverID: nil, tools: nil, detail: "Documentation could not be read", recordedAt: Date())
        try store.recordMCPSetup(first, in: chat.id)
        try store.recordMCPSetup(second, in: chat.id)
        chat.append(ChatMessage(role: .assistant, text: "A succeeded; B failed", state: .failed))
        store.save(chat)
        let reloaded = ChatHistoryStore(directory: directory)
        let outcomes = try reloaded.mcpSetupOutcomes(in: chat.id)
        expect(outcomes.contains(first) && outcomes.contains(second),
               "per-server native facts survive a failed batch reply and database reload")
        expect(try reloaded.mcpSetupOutcomes(in: UUID()).isEmpty, "setup facts stay scoped to their conversation")
        let cancelled = MCPSetupOutcome(source: second.source, name: second.name, state: .cancelled,
            serverID: nil, tools: nil, detail: "Review cancelled", recordedAt: Date())
        try reloaded.recordMCPSetup(cancelled, in: chat.id)
        let updated = try reloaded.mcpSetupOutcomes(in: chat.id)
        expect(updated.count == 2 && updated.contains(first) && updated.contains(cancelled),
               "a changed outcome replaces that server only, preserving earlier success")
    }

    @MainActor static func nativeReceiptWaitsForTheStreamingReply() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ChatHistoryStore(directory: directory)
        let chat = AIChatState(history: history)
        let (events, reply) = AIProviderStream.makeStream()
        expect(chat.send("MCP setup", using: HoldingProvider(events: events)), "the real chat state starts the model reply")
        let outcome = MCPSetupOutcome(source: source, name: "Calendar", state: .connected,
            serverID: UUID(), tools: 13, detail: "Connection test passed", recordedAt: Date())
        chat.recordSetupOutcome(outcome)
        expect(chat.session.messages.last?.state == .streaming,
               "native completion while the model streams does not replace the active reply")
        reply.yield(.text("Review opened"))
        reply.yield(.finished)
        reply.finish()
        for _ in 0..<400 {
            if !chat.isStreaming { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        expect(chat.session.messages.last?.toolUses.first?.title == "Calendar · Connected · 13 tools",
               "the app publishes a compact native result after the model reply")
        expect(chat.session.messages.last?.text == "" && chat.session.historyMessages.count == 2,
               "native receipts remain UI status rather than fabricated assistant prose in model context")
        let loaded = ChatHistoryStore(directory: directory).session(id: chat.session.id)
        expect(loaded?.messages.last?.toolUses.first?.title == "Calendar · Connected · 13 tools",
               "native results survive saving and reopening the conversation")
    }

    struct HoldingProvider: AIProvider {
        let events: AIProviderStream
        func stream(_ request: AIRequest) -> AIProviderStream { events }
    }

    @MainActor static func nativeToolsAreAvailableWithoutPhraseRouting() async throws {
        expect(Set(MCPSetupTools.tools.map(\.name)).count == 3, "documentation, review and status are exposed as tools")
        let server = MCPSetupToolServer()
        defer { server.stop() }
        let calls = Calls()
        let chat = UUID()
        let offer = try await server.server(for: chat) { call in
            calls.names.append(call.name)
            return AIToolResult(callID: call.id, content: "native result", isError: false)
        }
        guard case .url(let address, let headerName, let secret) = offer.transport,
            let url = URL(string: address) else { throw AIProviderError.malformedResponse }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        func post(_ method: String, _ params: [String: Any], authorized: Bool = true) async throws -> (Data, Int) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if authorized { request.setValue(secret, forHTTPHeaderField: headerName) }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc":"2.0", "id":1,
                                                                          "method":method, "params":params])
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let initialized = try await post("initialize", ["protocolVersion":"2025-03-26"])
        expect(initialized.1 == 200, "the actual local MCP endpoint initializes")
        let listed = try await post("tools/list", [:])
        let listing = try JSONSerialization.jsonObject(with: listed.0) as? [String: Any]
        let offered = (listing?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        expect(offered?.count == 3, "CLI clients see the same three native actions as API clients")
        let unauthorized = try await post("tools/call", ["name":MCPSetupTools.review], authorized: false)
        expect(unauthorized.1 == 401 && calls.names.isEmpty, "a caller without the in-memory credential cannot invoke setup")
        for text in ["Apple Calendar MCP 설치 해줘.", "continue", "그 작업 이어서 진행", "설치하지 마"] {
            let result = try await post("tools/call", ["name":MCPSetupTools.status, "arguments":["conversation_id":chat.uuidString, "context":text]])
            expect(result.1 == 200, "the tool endpoint does not classify or reject user phrasing: \(text)")
        }
        expect(calls.names == Array(repeating: MCPSetupTools.status, count: 4),
               "only model-selected actions are invoked; the bridge does not infer installation from words")
        let other = try await server.server(for: UUID()) { call in
            AIToolResult(callID: call.id, content: "other conversation", isError: false)
        }
        expect(other == offer, "parallel conversations share a stable CLI server configuration without restarting each other")
    }

    @MainActor final class Calls { var names: [String] = [] }
}
