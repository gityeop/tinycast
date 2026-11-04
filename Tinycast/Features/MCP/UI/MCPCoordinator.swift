import Foundation
import Observation
import SwiftUI
import OSLog

/// MCP's action surface: what is running, what the model may call, and who is asked first.
@MainActor
@Observable
final class MCPCoordinator {
    private let settings: AppSettings
    private let store: MCPSettingsStore
    private let manager: MCPServerManager
    private unowned let core: AppCore

    /// Servers each conversation was granted; keyed, since a dialog may outlive a chat switch.
    @ObservationIgnored private var chatGrants: [UUID: Set<UUID>] = [:]
    private struct SetupReview {
        let server: MCPServer
        let proposal: MCPInstallProposal
        let sources: [URL]
        let chat: UUID
        let source: URL
        var failure: MCPSetupOutcome?
        var id: UUID { server.id }
    }
    @ObservationIgnored private var setupReview: SetupReview?
    @ObservationIgnored private var setupQueue: [SetupReview] = []
    @ObservationIgnored private var isInstallingSetup = false
    @ObservationIgnored private var setupDocuments: [UUID: [URL: MCPDocumentation]] = [:]
    @ObservationIgnored private var installationTask: Task<Void, Never>?
    @ObservationIgnored private lazy var setupWindow = AppWindowController(
        title: "Review MCP Setup", contentSize: CGSize(width: 620, height: 660),
        activation: core.activationPolicy, closesOnEscape: true)

    init(
        settings: AppSettings, store: MCPSettingsStore, manager: MCPServerManager, core: AppCore
    ) {
        self.settings = settings
        self.store = store
        self.manager = manager
        self.core = core
    }

    var isActive: Bool {
        settings.aiEnabled && (settings.mcpEnabled || !enabledServers.isEmpty)
    }

    private var enabledServers: [MCPServer] {
        store.enabledServers(externalEnabled: settings.mcpEnabled)
    }

    /// Off means off: no connection, no resident process, and nothing offered to a model.
    func applyEnabled() {
        defer { dropWithdrawnServers() }
        installationTask?.cancel()
        guard isActive else {
            if !settings.aiEnabled || isInstallingSetup, let review = setupReview {
                setupQueue = []
                setupWindow.close()
                finishSetup(review.id)
            }
            core.mcpOAuth.stop()
            manager.stop()
            core.mcpInstallations.stopAll()
            return
        }
        if !settings.mcpEnabled { core.mcpOAuth.stop() }
        let enabled = enabledServers.filter { $0.trust != .never }
        var kept = Set(enabled.map(\.id))
        if isInstallingSetup, let review = setupReview { kept.insert(review.id) }
        core.mcpInstallations.retain(kept)
        let own = ownServers
        installationTask = Task { [weak self] in
            guard let self else { return }
            var ready = Set<UUID>()
            for server in enabled {
                guard !Task.isCancelled else { return }
                do {
                    try await self.core.mcpInstallations.ensureServices(
                        for: server, environment: self.store.isBuiltIn(server.id)
                            ? [:] : MCPSecretStore().secrets(for: server.id).environment)
                    ready.insert(server.id)
                } catch {
                    Logger(subsystem: "com.gityeop.tinycast", category: "MCPInstallation")
                        .error("Required service unavailable: \(error.localizedDescription, privacy: .private)")
                    self.manager.disconnect(server.id)
                }
            }
            guard !Task.isCancelled else { return }
            self.manager.reconcile(own.filter { ready.contains($0.id) })
        }
    }

    /// The Codex helper keeps what it was launched with, so a server taken away is taken from it.
    private func dropWithdrawnServers(besides withdrawn: UUID? = nil) {
        let offered = enabledServers.filter { $0.trust != .never && $0.id != withdrawn }
        var handles = isActive ? Set(offered.map(\.slug)) : []
        if settings.aiEnabled { handles.insert(MCPSetupTools.handle) }
        core.chatGPTSubscription.dropWithdrawnServers(keeping: handles)
    }

    /// Connecting on the way into chat, so the first send does not wait on every handshake.
    func warmUp() {
        guard isActive else { return }
        applyEnabled()
    }

    /// What Tinycast runs itself; Codex and Claude start their own copy of every local server.
    private var ownServers: [MCPServer] {
        let cliRoute = core.aiChatCoordinator.everyChatRunsItsOwnTools
        return enabledServers.filter { $0.runsInTinycast(whileCLIRouteSelected: cliRoute) }
    }

    var slugs: Set<String> {
        guard isActive else { return [] }
        return Set(enabledServers.map(\.slug))
    }

    /// What a chat's tools menu lists; empty while MCP is off.
    var servers: [MCPServer] {
        guard isActive else { return [] }
        return enabledServers
    }

    func server(slug: String) -> MCPServer? {
        guard isActive else { return nil }
        return enabledServers.first { $0.slug == slug }
    }

    /// What this turn may reach: everything enabled, or one server when `@slug` named it.
    func tools(scopedTo slug: String?) -> [AITool] {
        guard isActive else { return [] }
        return manager.tools
            .filter { tool in
                guard slug == nil || tool.serverSlug == slug else { return false }
                guard let server = server(slug: tool.serverSlug), server.id == tool.serverID else { return false }
                return server.trust != .never
            }
            .map { tool in
                tool.aiTool(resultByteLimit: store.isBuiltIn(tool.serverID) ? 131_072 : nil)
            }
    }

    /// The same list for a CLI route; it starts its own copies, so Tinycast's need not be ready.
    func toolServers(scopedTo slug: String?) async -> [AIToolServer] {
        guard isActive else { return [] }
        let secrets = MCPSecretStore()
        var result: [AIToolServer] = []
        for server in enabledServers
        where server.trust != .never && (slug == nil || server.slug == slug) {
            let stored = store.isBuiltIn(server.id) ? MCPSecretStore.Secrets() : secrets.secrets(for: server.id)
            do {
                try await core.mcpInstallations.ensureServices(for: server, environment: stored.environment)
            } catch { continue }
            var bearer: String?
            if server.oauth == true { bearer = try? await core.mcpOAuth.lentToken(for: server) }
            guard
                let toolServer = server.toolServer(
                    headerValue: stored.headerValue, environment: stored.environment,
                    bearerToken: bearer)
            else { continue }
            result.append(toolServer)
        }
        return result
    }

    /// Consent for a call a vendor CLI is making, through the same policy and the same dialog.
    func permit(_ call: AIToolServerCall, in chat: UUID) async -> Bool {
        guard isActive, let server = server(slug: call.handle) else { return false }
        return await isPermitted(server, tool: call.tool, in: chat)
    }

    func invoke(_ call: AIToolCall, in chat: UUID) async -> AIToolResult {
        guard let route = MCPToolName.parse(call.name),
            let server = server(slug: route.slug),
            let connection = manager.connection(slug: route.slug)
        else {
            return .failure(call.id, "That tool is no longer connected.")
        }
        guard await isPermitted(server, tool: route.tool, in: chat) else {
            return .failure(call.id, "The user declined this tool call.")
        }
        manager.markUsed()
        do {
            try await core.mcpInstallations.ensureServices(
                for: server, environment: self.store.isBuiltIn(server.id)
                            ? [:] : MCPSecretStore().secrets(for: server.id).environment)
            let (content, isError) = try await connection.call(
                route.tool, arguments: JSONValue(data: Data(call.arguments.utf8)) ?? .object([:]))
            return AIToolResult(callID: call.id, content: content, isError: isError)
        } catch {
            return .failure(call.id, error.localizedDescription)
        }
    }

    func signIn(_ server: MCPServer, credentials: MCPOAuth.Credentials) async throws {
        guard isActive else { throw MCPOAuth.Failure.signInRequired }
        manager.disconnect(server.id)
        try await core.mcpOAuth.signIn(server: server, credentials: credentials)
    }

    func signOut(_ id: UUID) throws {
        manager.disconnect(id)
        try core.mcpOAuth.signOut(id)
        dropWithdrawnServers(besides: id)
    }

    func cancelSignIn(_ id: UUID) { core.mcpOAuth.cancelSignIn(id) }

    func status(of id: UUID) -> MCPServerStatus {
        if let failure = core.mcpInstallations.failures[id] { return .failed(failure) }
        return manager.status(of: id)
    }

    func installationProgress(for id: UUID) -> String? { core.mcpInstallations.progress[id] }

    func statusLabel(for server: MCPServer) -> String {
        if server.trust == .never { return "Not allowed" }
        if isActive, enabledServers.contains(where: { $0.id == server.id }),
            !server.runsInTinycast(whileCLIRouteSelected: core.aiChatCoordinator.everyChatRunsItsOwnTools)
        {
            return "Ready in chat"
        }
        return status(of: server.id).label
    }

    func save(_ server: MCPServer, secrets: MCPSecretStore.Secrets) throws {
        if !store.isBuiltIn(server.id) { try MCPSecretStore().save(secrets, for: server.id) }
        if store.server(id: server.id) != nil { core.mcpInstallations.stop(server.id) }
        core.mcpOAuth.cancelSignIn(server.id)
        manager.disconnect(server.id)
        store.save(server)
        applyEnabled()
    }

    func remove(_ id: UUID) throws {
        core.mcpOAuth.cancelSignIn(id)
        try MCPSecretStore().remove(for: id)
        core.mcpInstallations.stop(id)
        store.remove(id: id)
        applyEnabled()
    }

    func discardUnsaved(_ id: UUID) {
        cancelSignIn(id)
        if store.server(id: id) == nil { try? MCPSecretStore().remove(for: id) }
    }

    func authenticationStatus(
        _ server: MCPServer, stored: MCPOAuth.Credentials?
    ) -> MCPOAuthManager.Status {
        core.mcpOAuth.status(for: server, stored: stored)
    }

    func test(_ server: MCPServer, secrets: MCPSecretStore.Secrets) async -> MCPServerStatus {
        do {
            try await core.mcpInstallations.ensureServices(for: server, environment: secrets.environment)
        } catch { return .failed("A required background service is unavailable.") }
        if server.oauth == true {
            let stored = MCPSecretStore().secrets(for: server.id).oauth
            guard stored?.clientID == secrets.oauth?.clientID,
                stored?.clientSecret == secrets.oauth?.clientSecret
            else { return .signInRequired }
        }
        let connection = MCPServerConnection(server: server, secrets: secrets, oauth: core.mcpOAuth)
        defer { connection.stop() }
        await connection.start()
        return connection.status
    }

    func setupContext(in chat: UUID) throws -> String {
        let outcomes = try core.chatHistory.mcpSetupOutcomes(in: chat)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(outcomes)
        let registered = store.servers.map { ["id": $0.id.uuidString, "name": $0.title, "enabled": String($0.isEnabled)] }
        let inventory = try JSONSerialization.data(withJSONObject: registered)
        guard let registeredText = String(data: inventory, encoding: .utf8),
            let outcomesText = String(data: json, encoding: .utf8) else { throw AIProviderError.malformedResponse }
        return "Oncast MCP state (native records), conversation_id=\(chat.uuidString):\nRegistered: " + registeredText
            + "\nThis conversation's outcomes: " + outcomesText
    }

    func invokeSetup(_ call: AIToolCall, in chat: UUID) async -> AIToolResult {
        guard settings.aiEnabled else { return .failure(call.id, "AI is disabled.") }
        do {
            let arguments = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any]
            let suppliedChat = (arguments?["conversation_id"] as? String).flatMap(UUID.init(uuidString:))
            guard suppliedChat == chat else {
                throw AIProviderError.responseFailed("The MCP action must use the current conversation ID.")
            }
            switch call.name {
            case MCPSetupTools.status:
                return AIToolResult(callID: call.id, content: try setupContext(in: chat), isError: false)
            case MCPSetupTools.read:
                guard let address = arguments?["url"] as? String, let source = URL(string: address) else {
                    throw AIProviderError.malformedResponse
                }
                let document = try await MCPDocumentationService.fetch(source)
                try Task.checkCancellation()
                setupDocuments[chat, default: [:]][source] = document
                let environment = try await MCPInstallationEnvironment.describe()
                return AIToolResult(callID: call.id, content: document.text + "\n\n" + environment, isError: false)
            case MCPSetupTools.review:
                guard let addresses = arguments?["sources"] as? [String], !addresses.isEmpty,
                    let configuration = arguments?["configuration"] as? [String: Any] else {
                    throw AIProviderError.malformedResponse
                }
                let sources = try addresses.map { address -> URL in
                    guard let source = URL(string: address), setupDocuments[chat]?[source] != nil else {
                        throw AIProviderError.responseFailed("Read the selected MCP documentation before presenting its plan.")
                    }
                    return source
                }
                if let existing = try core.chatHistory.mcpSetupOutcomes(in: chat).first(where: {
                    $0.source == sources[0] && $0.state == .connected
                }), let id = existing.serverID, store.server(id: id) != nil {
                    return AIToolResult(callID: call.id, content: "Already registered. " + existing.detail, isError: false)
                }
                let documents = sources.compactMap { setupDocuments[chat]?[$0] }
                let evidence = documents.map(\.text).joined(separator: "\n\n")
                let encoded = try JSONSerialization.data(withJSONObject: configuration)
                guard let configurationText = String(data: encoded, encoding: .utf8) else {
                    throw AIProviderError.malformedResponse
                }
                let proposal = try MCPInstallProposal.parse(configurationText, document: evidence)
                let allSources = documents.flatMap(\.sources)
                let result = try reviewSetup(proposal, sources: allSources, in: chat, source: sources[0])
                return AIToolResult(callID: call.id, content: result, isError: false)
            default:
                throw AIProviderError.responseFailed("Unknown Oncast setup action.")
            }
        } catch {
            Logger(subsystem: "com.gityeop.tinycast", category: "MCPSetup")
                .error("Native setup action failed: \(error.localizedDescription, privacy: .private)")
            let message = (error as? AIProviderError)?.errorDescription ?? "The MCP setup action could not finish."
            if let object = try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any],
                let address = (object["sources"] as? [String])?.first ?? object["url"] as? String,
                let source = URL(string: address) {
                do {
                    try core.chatHistory.recordMCPSetup(MCPSetupOutcome(source: source, name: source.lastPathComponent,
                        state: .failed, serverID: nil, tools: nil, detail: message, recordedAt: Date()), in: chat)
                } catch {
                    return .failure(call.id, "The MCP action and saving its outcome failed.")
                }
            }
            return .failure(call.id, message)
        }
    }

    func reviewSetup(
        _ proposal: MCPInstallProposal, sources: [URL], in chat: UUID, source: URL
    ) throws -> String {
        guard settings.aiEnabled else { throw CancellationError() }
        let server = proposal.server()
        let outcome = MCPSetupOutcome(source: source, name: server.title, state: .awaitingApproval,
            serverID: nil, tools: nil, detail: "Native approval pending.", recordedAt: Date())
        try core.chatHistory.recordMCPSetup(outcome, in: chat)
        setupQueue.append(SetupReview(server: server, proposal: proposal, sources: sources, chat: chat, source: source))
        showNextSetup()
        return "Native approval pending. Oncast will publish the installation and connection test result in this chat."
    }

    private func showNextSetup() {
        guard setupReview == nil, settings.aiEnabled, !setupQueue.isEmpty else { return }
        let review = setupQueue.removeFirst()
        setupReview = review
        let id = review.id
        setupWindow.onClose = { [weak self] in
            guard let self, self.setupReview?.id == id else { return }
            do {
                if self.setupReview?.failure == nil {
                    let blocked = !review.proposal.installation.blockers.isEmpty
                    try self.recordSetup(MCPSetupOutcome(source: review.source, name: review.server.title,
                        state: blocked ? .blocked : .cancelled, serverID: nil, tools: nil,
                        detail: blocked ? review.proposal.installation.blockers.joined(separator: "\n") : "Review cancelled.",
                        recordedAt: Date()), in: review.chat)
                }
            } catch { self.core.showMessage("The MCP setup result could not be saved.", tone: .danger) }
            self.finishSetup(id)
        }
        setupWindow.show {
            MCPServerEditor(
                target: MCPServerEditorTarget(server: review.server, isNew: true, proposal: review.proposal,
                    sources: review.sources, installationRoot: core.mcpInstallations.directory(for: id)),
                onSave: { _, _ in "Use Approve & Set Up." },
                onCancel: { [weak self] in self?.setupWindow.close() },
                onInstall: { [weak self] server, secrets in
                    guard let self, self.setupReview?.id == id else { throw CancellationError() }
                    self.setupReview?.failure = nil
                    do {
                        try self.core.chatHistory.recordMCPSetup(MCPSetupOutcome(source: review.source,
                            name: server.title, state: .installing, serverID: nil, tools: nil,
                            detail: "Approved; installation in progress.", recordedAt: Date()), in: review.chat)
                        let count = try await self.installReviewed(server, secrets: secrets, plan: review.proposal.installation)
                        try self.recordSetup(MCPSetupOutcome(source: review.source, name: server.title, state: .connected,
                            serverID: server.id, tools: count, detail: "Registered; initialize and tools/list passed.",
                            recordedAt: Date()), in: review.chat)
                        self.finishSetup(id)
                    } catch {
                        let outcome = MCPSetupOutcome(source: review.source, name: server.title, state: .failed,
                            serverID: nil, tools: nil, detail: (error as? AIProviderError)?.errorDescription
                                ?? "MCP setup could not finish.", recordedAt: Date())
                        self.setupReview?.failure = outcome
                        try self.recordSetup(outcome, in: review.chat)
                        throw error
                    }
                })
                .environment(self)
        }
    }

    private func recordSetup(_ outcome: MCPSetupOutcome, in chat: UUID) throws {
        try core.chatHistory.recordMCPSetup(outcome, in: chat)
        core.aiChatCoordinator.recordSetupOutcome(outcome, in: chat)
    }

    private func installReviewed(
        _ server: MCPServer, secrets: MCPSecretStore.Secrets, plan: MCPInstallPlan
    ) async throws -> Int {
        guard settings.aiEnabled else { throw CancellationError() }
        isInstallingSetup = true
        var completed = false
        defer {
            isInstallingSetup = false
            if !completed { core.mcpInstallations.stop(server.id) }
        }
        guard !store.servers.contains(where: { $0.transport == server.transport }) else {
            throw AIProviderError.responseFailed("This server is already registered. Edit it in Settings → AI → MCP.")
        }
        settings.mcpEnabled = true
        var secrets = secrets
        if server.oauth == true {
            guard let credentials = secrets.oauth else { throw MCPOAuth.Failure.signInRequired }
            try await signIn(server, credentials: credentials)
            secrets.oauth = MCPSecretStore().secrets(for: server.id).oauth
        }
        try Task.checkCancellation()
        let configured = try await core.mcpInstallations.prepare(plan, server: server, environment: secrets.environment)
        let status = await test(configured, secrets: secrets)
        try Task.checkCancellation()
        guard case .ready(let tools) = status else {
            Logger(subsystem: "com.gityeop.tinycast", category: "MCPSetup")
                .error("MCP setup connection test failed: \(String(describing: status), privacy: .private)")
            throw AIProviderError.responseFailed(
                "Connection test failed. Check the endpoint, command, required runtime and credentials. "
                    + "The server has not been registered.")
        }
        try core.mcpInstallations.commit(plan, server: configured)
        try save(configured, secrets: secrets)
        completed = true
        return tools
    }

    private func finishSetup(_ id: UUID) {
        guard setupReview?.id == id else { return }
        setupReview = nil
        if isInstallingSetup { core.mcpInstallations.stop(id) }
        setupWindow.close()
        Task { @MainActor [weak self] in self?.showNextSetup() }
    }

    private func isPermitted(_ server: MCPServer, tool: String, in chat: UUID) async -> Bool {
        switch MCPTrustPolicy.decide(
            trust: server.trust, isGrantedForChat: chatGrants[chat]?.contains(server.id) == true)
        {
        case .allow: return true
        case .refuse: return false
        case .ask: break
        }
        switch await ask(server, tool: tool) {
        case .always:
            store.setTrust(.always, for: server.id)
            return true
        case .thisChat:
            chatGrants[chat, default: []].insert(server.id)
            return true
        case .refuse:
            return false
        }
    }

    /// Escape refuses this one call: a dialog can grant a server, only Settings can withhold one.
    private func ask(_ server: MCPServer, tool: String) async -> MCPTrustChoice {
        let choices: [MCPTrustChoice] = [.always, .thisChat, .refuse]
        let index = await core.choose(
            title: "Let \(server.title) run its tools?",
            message: store.isBuiltIn(server.id)
                ? "The model wants to call \u{201C}\(tool)\u{201D} on your open canvas. "
                    + "Canvas changes can be undone in Excalidraw."
                : "The model wants to call \u{201C}\(tool)\u{201D}. Oncast did not write this "
                    + "server and cannot vouch for what it does.",
            symbol: "wrench.and.screwdriver",
            options: [
                DialogAction(title: "Always Allow"),
                DialogAction(title: "Allow This Chat"),
                DialogAction(title: "Don't Allow", role: .cancel)
            ],
            defaultIndex: 1)
        return choices.indices.contains(index) ? choices[index] : .refuse
    }
}
