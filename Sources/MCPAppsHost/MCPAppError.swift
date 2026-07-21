import Foundation

/// Typed errors for MCP App operations.
public enum MCPAppError: Error, Sendable {
    /// Server connection failed or timed out.
    case serverUnreachable(underlying: any Error)

    /// The ui:// resource URI was not found on the server.
    case resourceNotFound(uri: String)

    /// Resource fetched but no resolver handles its MIME type.
    case unsupportedContentType(mimeType: String)

    /// Content resolver failed (BindJS compilation error, malformed HTML, etc.)
    case contentResolutionFailed(underlying: any Error)

    /// Tool execution returned an error result.
    case toolFailed(result: ToolResult)

    /// Cancelled via session.cancel().
    case cancelled
}

extension MCPAppError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .serverUnreachable(let err):
            return "Server unreachable: \(err.localizedDescription)"
        case .resourceNotFound(let uri):
            return "Resource not found: \(uri)"
        case .unsupportedContentType(let mime):
            return "Unsupported content type: \(mime)"
        case .contentResolutionFailed(let err):
            return "Content resolution failed: \(err.localizedDescription)"
        case .toolFailed(let result):
            let detail = result.content.compactMap {
                if case .text(let t) = $0 { return t }
                return nil
            }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty { return "Tool execution failed" }
            let preview = detail.count > 500 ? String(detail.prefix(500)) + "…" : detail
            return "Tool execution failed: \(preview)"
        case .cancelled:
            return "Cancelled"
        }
    }
}
