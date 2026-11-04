import Darwin
import Foundation
import Synchronization

@MainActor
final class MCPInstallProcess {
    private final class Capture: Sendable {
        let output = Mutex("")
    }

    private let terminal: PseudoTerminal
    private let capture: Capture
    private let exit: Task<Int32, Never>
    private var monitor: Task<Void, Never>?
    private(set) var status: Int32?

    private init(terminal: PseudoTerminal) {
        self.terminal = terminal
        let capture = Capture()
        self.capture = capture
        let exit = Task.detached {
            var buffer = [UInt8](repeating: 0, count: 8_192)
            while true {
                let count = read(terminal.parentEnd, &buffer, buffer.count)
                guard count > 0 else { break }
                let text = String(decoding: buffer.prefix(count), as: UTF8.self)
                capture.output.withLock { output in
                    output += text
                    if output.utf8.count > 16_384 { output = String(output.suffix(8_192)) }
                }
            }
            let status = terminal.wait()
            terminal.close()
            return status
        }
        self.exit = exit
        monitor = Task { [weak self] in self?.status = await exit.value }
    }

    static func start(
        command: String, arguments: [String], directory: URL, environment: [String: String]
    ) async throws -> MCPInstallProcess {
        let executable: URL
        if command.contains("/") {
            executable = command.hasPrefix("/") ? URL(fileURLWithPath: command) : directory.appending(path: command)
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw AIProviderError.responseFailed("The planned executable is missing: \(command). Setup stopped.")
            }
        } else {
            guard let found = await ExecutableLocator.locate(command) else {
                throw AIProviderError.responseFailed("The planned executable \(command) is not installed. Setup stopped.")
            }
            executable = found
        }
        try Task.checkCancellation()
        guard let terminal = PseudoTerminal.spawn(
            executable: executable.path, arguments: arguments,
            environment: ExecutableLocator.environment(running: executable, adding: environment),
            workingDirectory: directory.path) else {
            throw AIProviderError.responseFailed("The planned command could not start in its working folder. Setup stopped.")
        }
        return MCPInstallProcess(terminal: terminal)
    }

    func wait() async throws -> Int32 {
        try await withTaskCancellationHandler {
            let status = await exit.value
            try Task.checkCancellation()
            return status
        } onCancel: {
            terminal.signalSession(SIGKILL)
        }
    }

    func stop() {
        if status == nil { terminal.signalSession(SIGKILL) }
    }

    func diagnostics(redacting values: [String]) -> String {
        var text = capture.output.withLock { $0 }
        for value in values where !value.isEmpty { text = text.replacingOccurrences(of: value, with: "[redacted]") }
        return text
    }
}
