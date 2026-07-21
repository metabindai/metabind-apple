import Foundation
import MCPAppsHost

/// A provider that streams responses from a large language model.
///
/// Conform to this protocol to integrate any LLM backend with ``MetabindAssistant``.
/// The assistant manages the conversation loop and tool execution; the provider
/// handles the API call and response streaming.
public protocol LLMProvider: Sendable {
    /// Stream a response for the given conversation.
    ///
    /// - Parameters:
    ///   - messages: The conversation history in normalized format.
    ///   - tools: Tool definitions the model can invoke, or `nil` if none available.
    ///   - systemPrompt: An optional system prompt prepended to the conversation.
    /// - Returns: An async stream of events representing the model's response.
    func stream(
        messages: [LLMMessage],
        tools: [LLMTool]?,
        systemPrompt: String?
    ) -> AsyncStream<LLMEvent>

    /// Whether the provider runs the tool-call loop itself and emits
    /// ``LLMEvent/toolResult(toolCallId:content:isError:)`` events in-stream.
    ///
    /// When `true` (e.g. the Metabind Agent proxy), ``MetabindAssistant``
    /// does not execute tools locally — it just renders what the provider
    /// emits. When `false` (direct-to-provider BYOK), the assistant runs the
    /// loop itself via `MCPServer.callTool` and feeds results back on the
    /// next turn.
    var runsToolsRemotely: Bool { get }

    /// Drop any server-side conversation state the provider is holding so
    /// the next turn starts fresh. Called from
    /// ``MetabindAssistant/reset()``.
    ///
    /// Providers that persist a `conversationId` (e.g. the Metabind Agent
    /// proxy) must clear it here; otherwise ``MetabindAssistant/reset()``
    /// clears local history but the next ``MetabindAssistant/send(_:)``
    /// re-submits under the same — possibly poisoned — server
    /// conversation. Stateless providers (BYOK direct-to-Anthropic) can
    /// rely on the default no-op.
    func resetConversation() async
}

extension LLMProvider {
    public var runsToolsRemotely: Bool { false }
    public func resetConversation() async {}
}

// MARK: - Conversation History

/// A message in the LLM conversation history.
///
/// This is the normalized format used between ``MetabindAssistant`` and ``LLMProvider``.
/// Each provider translates to its own wire format internally.
public enum LLMMessage: Sendable {
    /// A user text message.
    case user(String)

    /// An assistant response containing optional text and tool calls.
    case assistant(text: String?, toolCalls: [LLMToolCall])

    /// Results from tool executions, sent back to the model.
    case toolResults([LLMToolResult])
}

/// A tool call requested by the model.
public struct LLMToolCall: Sendable {
    public let id: String
    public let name: String
    public let arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// The result of executing a tool, sent back to the model.
public struct LLMToolResult: Sendable {
    public let toolCallId: String
    public let content: String
    public let isError: Bool

    public init(toolCallId: String, content: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}

/// A tool definition passed to the model for function calling.
public struct LLMTool: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

// MARK: - Stream Events

/// Events emitted during model response streaming.
public enum LLMEvent: Sendable {
    /// A fragment of text output.
    case textDelta(String)

    /// A tool call has started. Argument deltas will follow.
    case toolCallStart(index: Int, id: String, name: String)

    /// A fragment of a tool call's argument JSON. Routed by `index` to the
    /// matching accumulator opened by ``toolCallStart(index:id:name:)``.
    /// Providers must pass the index explicitly — assistants don't infer
    /// "the latest open block," since the provider-agnostic agent contract
    /// permits id-tagged interleaving across content blocks.
    case toolCallArgumentDelta(index: Int, fragment: String)

    /// Canonical, fully-parsed arguments for a tool call. Optional override
    /// emitted by providers that send a terminal authoritative input (e.g.
    /// the Metabind Agent's `tool_use` frame after `tool_use_input_partial`
    /// streaming). When present, the assistant prefers this over the
    /// accumulated `toolCallArgumentDelta` buffer — covering the cases
    /// where partials are absent, lossy, or fail to concatenate to valid
    /// JSON. Providers that don't send a terminal frame (e.g. BYOK
    /// Anthropic) simply never emit this event.
    case toolCallArgumentsFinal(index: Int, arguments: JSONValue)

    /// The content block at the given index has finished.
    case contentBlockStop(index: Int)

    /// The response is complete.
    case done(stopReason: LLMStopReason)

    /// A tool call was executed remotely by the provider (e.g. the Metabind
    /// Agent proxy). The assistant renders the result in the matching session
    /// but does **not** call `MCPServer.callTool` itself.
    ///
    /// - `content` is the flattened text of the MCP `content` array, suitable
    ///   for display in a plain session UI.
    /// - `structuredContent` is preserved verbatim when the tool returned it,
    ///   so downstream consumers (e.g. interactive BindJS renderers) can
    ///   access the structured payload without reparsing `content`.
    case toolResult(
        toolCallId: String,
        content: String,
        structuredContent: JSONValue?,
        isError: Bool
    )

    /// The primary provider exhausted retries and the agent service switched
    /// to a failover provider mid-turn. Informational — the stream
    /// continues on the new provider.
    case providerSwitch(from: String, to: String, reason: String)

    /// A stream-level error.
    case error(any Error)
}

/// The reason the model stopped generating.
public enum LLMStopReason: Sendable, Equatable {
    case endTurn
    case toolUse
    case maxTokens
    case unknown(String)

    public static func == (lhs: LLMStopReason, rhs: LLMStopReason) -> Bool {
        switch (lhs, rhs) {
        case (.endTurn, .endTurn), (.toolUse, .toolUse), (.maxTokens, .maxTokens): true
        case (.unknown(let a), .unknown(let b)): a == b
        default: false
        }
    }
}
