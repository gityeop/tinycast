import Foundation

enum MCPSetupTools {
    static let handle = "oncast-setup"
    static let read = "oncast_read_mcp_documentation"
    static let review = "oncast_review_mcp_setup"
    static let status = "oncast_mcp_status"

    static let tools: [AITool] = [
        AITool(name: read, description: """
            Read public MCP documentation and available local runtimes. Use conversation_id from native state.
            """,
            parameters: .object(["type": .string("object"), "properties": .object([
                "conversation_id": .object(["type": .string("string")]),
                "url": .object(["type": .string("string"), "description": .string("Public HTTPS documentation URL")])
            ]), "required": .array([.string("conversation_id"), .string("url")]), "additionalProperties": .bool(false)]),
            origin: "Oncast", title: "Read MCP documentation"),
        AITool(name: review, description: """
            Present an MCP installation plan for native approval using conversation_id from native state.
            Returns immediately with approval pending. Oncast owns approval, installation and connection
            testing and posts a native result in the chat. Multiple plans queue separate approval screens.
            sources must be documentation URLs read with oncast_read_mcp_documentation in this conversation.
            The first source identifies the server. configuration is the installation plan.
            \(MCPInstallProposal.instructions)
            """, parameters: .object(["type": .string("object"), "properties": .object([
                "conversation_id": .object(["type": .string("string")]),
                "sources": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "configuration": .object(["type": .string("object")])
            ]), "required": .array([.string("conversation_id"), .string("sources"), .string("configuration")]),
            "additionalProperties": .bool(false)]), origin: "Oncast", title: "Review MCP setup"),
        AITool(name: status, description: """
            Read registered servers and setup outcomes. Use conversation_id from native state.
            """,
            parameters: .object(["type": .string("object"), "properties": .object([
                "conversation_id": .object(["type": .string("string")])
            ]), "required": .array([.string("conversation_id")]), "additionalProperties": .bool(false)]),
            origin: "Oncast", title: "MCP status")
    ]

    static func owns(_ name: String) -> Bool { tools.contains { $0.name == name } }
}
