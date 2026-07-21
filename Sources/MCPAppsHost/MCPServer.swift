import Foundation

/// What the framework needs from your MCP connection.
/// Conform your existing MCP client.
public protocol MCPServer: Sendable {
    /// Execute a tool on the MCP server.
    func callTool(name: String, arguments: JSONValue) async throws -> ToolResult

    /// Read a resource from the MCP server.
    func readResource(uri: String) async throws -> ResourceContent

    /// Discover available tools. Default returns empty.
    func listTools() async throws -> [MCPToolDefinition]
}

public extension MCPServer {
    func listTools() async throws -> [MCPToolDefinition] { [] }

    /// Execute a tool and unwrap the result into the consumer-facing shape.
    ///
    /// Matches the web renderer's `MCPHost.toolCall` semantics:
    /// 1. If the tool errored, throws `MCPAppError.toolFailed`.
    /// 2. Takes the first text block; if it parses as JSON, returns the
    ///    parsed value (object / array / primitive).
    /// 3. Falls back to the raw text string.
    /// 4. Returns `nil` if the result has no usable content.
    ///
    /// BindJS components consuming `useMCPHost().toolCall(...)` expect this
    /// shape — not the raw `ToolResult` envelope.
    func callToolUnwrapped(name: String, arguments: JSONValue) async throws -> Any? {
        let result = try await callTool(name: name, arguments: arguments)
        if result.isError {
            throw MCPAppError.toolFailed(result: result)
        }
        for block in result.content {
            if case .text(let text) = block {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = trimmed.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    return parsed
                }
                return text
            }
        }
        return nil
    }
}
