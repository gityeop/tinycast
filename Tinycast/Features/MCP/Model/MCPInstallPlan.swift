import Foundation

struct MCPInstallPlan: Codable, Equatable, Sendable {
    struct Step: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case command, service }
        let title: String
        let kind: Kind
        let command: String
        let arguments: [String]
        let directory: String
        let readyPort: Int
        let evidence: String
    }

    let directory: String
    let steps: [Step]
    let blockers: [String]

    static let none = MCPInstallPlan(directory: ".", steps: [], blockers: [])

    func validate(document: String) throws {
        try Self.validateDirectory(directory)
        for step in steps {
            try Self.validateDirectory(step.directory)
            guard !step.title.isEmpty, !step.command.isEmpty,
                !step.evidence.isEmpty, document.contains(step.evidence) else {
                throw AIProviderError.responseFailed("An installation step is missing its documentation evidence.")
            }
            if blockers.isEmpty, step.kind == .service, !(1...65_535).contains(step.readyPort) {
                throw AIProviderError.responseFailed("A background service needs its documented local readiness port.")
            }
        }
    }

    static func validateDirectory(_ path: String) throws {
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), !path.split(separator: "/").contains("..") else {
            throw AIProviderError.responseFailed("Installation working folders must stay inside this setup's private folder.")
        }
    }

    static func resolve(_ value: String, root: URL) -> String {
        value.replacingOccurrences(of: "{install}", with: root.path)
    }

    static func folder(_ relative: String, root: URL) -> URL {
        root.appending(path: relative, directoryHint: .isDirectory).standardizedFileURL
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    func launcher(command: String, arguments: [String], root: URL) -> String {
        let argv = ([command] + arguments).map { Self.shellQuote(Self.resolve($0, root: root)) }.joined(separator: " ")
        let executableFolder = URL(fileURLWithPath: Self.resolve(command, root: root)).deletingLastPathComponent().path
        return "#!/bin/sh\nset -eu\nPATH=" + Self.shellQuote(executableFolder + ":/opt/homebrew/bin:/usr/local/bin")
            + ":\"$PATH\"\nexport PATH\ncd " + Self.shellQuote(Self.folder(directory, root: root).path)
            + "\nexec " + argv + "\n"
    }
}
