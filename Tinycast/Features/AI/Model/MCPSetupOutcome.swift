import Foundation

struct MCPSetupOutcome: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case awaitingApproval, installing, connected, cancelled, failed, blocked }
    let source: URL
    let name: String
    let state: State
    let serverID: UUID?
    let tools: Int?
    let detail: String
    let recordedAt: Date
    func receipt(messageID: UUID, callID: String) -> ChatMessage {
        var label: String
        switch state {
        case .awaitingApproval: label = "Awaiting approval"
        case .installing: label = "Installing"
        case .connected: label = "Connected"
        case .cancelled: label = "Cancelled"
        case .failed: label = "Failed"
        case .blocked: label = "Blocked"
        }
        if let tools { label += " · \(tools) tools" }
        return ChatMessage(id: messageID, role: .assistant, text: "", sentAt: recordedAt, toolUses: [
            ChatToolUse(callID: callID, origin: "Oncast Setup", title: name + " · " + label,
                        state: state == .failed || state == .blocked ? .failed : .completed,
                        textOffset: 0, sequence: 0)
        ])
    }
}
