import Foundation

enum MCPInstallationEnvironment {
    static func describe() async throws -> String {
        let commands = ["git", "node", "npm", "python3", "uv", "swift", "cargo", "brew", "docker"]
        let available = try await withThrowingTaskGroup(of: (String, String?).self) { group in
            for command in commands {
                group.addTask {
                    guard let executable = await ExecutableLocator.locate(command) else { return (command, nil) }
                    if command == "node" {
                        let version = try version(of: executable)
                        return (command, executable.path + " (" + version + ")")
                    }
                    return (command, executable.path)
                }
            }
            var rows: [String] = []
            for try await (command, path) in group {
                rows.append(command + ": " + (path ?? "not installed"))
            }
            return rows.sorted().joined(separator: "\n")
        }
        return "This Mac's executables:\n" + available
            + "\nInclude installation steps for missing required runtimes when the documentation supports a method. "
            + "Otherwise list the missing runtime and required manual action as a blocker. "
            + "No administrator password is available."
    }
    nonisolated private static func version(of executable: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let version = String(data: output, encoding: .utf8) else {
            throw AIProviderError.responseFailed("The installed Node.js version could not be read.")
        }
        return version.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
