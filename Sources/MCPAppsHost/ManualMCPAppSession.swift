import Foundation

/// Session where you control tool execution.
///
/// `feed` and `complete` only exist here — not on MCPAppSession.
/// If you don't need them, you don't see them.
///
///     let session = ManualMCPAppSession(toolCall: call, server: myServer)
///
///     for await chunk in llm.streamArguments(call) {
///         session.feed(chunk)
///     }
///
///     let result = try await myPipeline.execute(call)
///     session.complete(with: result)
///
public final class ManualMCPAppSession: MCPAppSession {

    public override init(toolCall: some MCPToolCall, server: some MCPServer, resolvers: [any ContentResolver] = defaultResolvers) {
        super.init(toolCall: toolCall, server: server, resolvers: resolvers, autoExecute: false)
    }

    /// Manual session from primitives.
    public convenience init(
        id: String,
        toolName: String,
        arguments: JSONValue = .object([:]),
        resourceUri: String? = nil,
        server: some MCPServer,
        resolvers: [any ContentResolver] = defaultResolvers
    ) {
        self.init(toolCall: Self.makeCall(id: id, toolName: toolName, arguments: arguments, resourceUri: resourceUri), server: server, resolvers: resolvers)
    }

    /// Stream partial tool arguments to the view.
    /// Call 0..n times. Each call updates the view progressively.
    public func feed(_ partialArguments: JSONValue) {
        self.partialArguments = partialArguments
    }

    /// Deliver the final tool result. Transitions to .completed(result).
    public func complete(with result: ToolResult) {
        if result.isError {
            transitionTo(.failed(.toolFailed(result: result)))
        } else {
            transitionTo(.completed(result))
        }
    }
}
