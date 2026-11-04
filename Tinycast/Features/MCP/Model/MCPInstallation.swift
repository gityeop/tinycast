import Foundation

struct MCPInstallation: Codable, Equatable, Sendable {
    let serverID: UUID
    let plan: MCPInstallPlan
    let environmentKeys: [String]
}
