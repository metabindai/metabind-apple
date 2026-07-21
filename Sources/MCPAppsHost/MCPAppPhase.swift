/// View-layer phase with rendered content. Used in the phase closure.
///
/// Mirrors MCPAppSession.Phase but carries MCPAppContent
/// in .active and .completed — like AsyncImagePhase carries Image in .success.
///
/// Two phase types, two purposes:
///   MCPAppSession.Phase  → Sendable, model layer, observe from anywhere
///   MCPAppPhase          → view layer, carries rendered content, phase closure only
///
public enum MCPAppPhase {
    case loading
    case active(MCPAppContent)
    case completed(MCPAppContent, ToolResult)
    case failed(MCPAppError)
    case cancelled

    /// Convenience: the rendered content, if available.
    public var content: MCPAppContent? {
        switch self {
        case .active(let c): return c
        case .completed(let c, _): return c
        default: return nil
        }
    }

    /// Convenience: the tool result, if completed.
    public var result: ToolResult? {
        if case .completed(_, let r) = self { return r }
        return nil
    }

    /// Convenience: the error, if failed.
    public var error: MCPAppError? {
        if case .failed(let e) = self { return e }
        return nil
    }
}
