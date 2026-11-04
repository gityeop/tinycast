import Foundation

enum CanvasMCPServer {
    static let id = UUID(uuidString: "A24BF68D-19C0-45E8-A876-709FE483CE42")!

    static func make(helperURL: URL) -> MCPServer {
        MCPServer(
            id: id, name: "Oncast Canvas", slug: "oncast-canvas",
            transport: .stdio(command: helperURL.path, arguments: [], environmentKeys: []))
    }
}
