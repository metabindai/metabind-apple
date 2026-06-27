import Foundation
import Observation
import MCPAppsHost
import os

private let log = Logger(subsystem: "MetabindAssistant", category: "Assistant")

/// A conversational AI assistant that orchestrates LLM responses and MCP tool execution.
///
/// `MetabindAssistant` manages the full conversation loop: sending user messages to an LLM
/// provider, detecting tool calls in the response, executing them against an MCP server,
/// rendering interactive results via `MCPAppSession`, and continuing the conversation
/// until the model finishes.
///
/// Tools are discovered automatically from the MCP server on first use.
/// Interactive tool results render as native SwiftUI via `MCPAppView`.
///
/// ## Usage
///
/// ```swift
/// let server = MCPAppsClient(url: mcpURL, headers: ["authorization": "Bearer \(key)"])
/// let provider = AnthropicProvider(apiKey: "sk-ant-...")
/// let assistant = MetabindAssistant(server: server, provider: provider)
///
/// struct ContentView: View {
///     var body: some View {
///         MetabindAssistantView(assistant: assistant)
///     }
/// }
/// ```
@MainActor
@Observable
public final class MetabindAssistant {

    /// The conversation history.
    public let conversation = Conversation()

    /// Whether the assistant is currently generating a response.
    public private(set) var isProcessing = false

    /// The MCP tools discovered from the server.
    public private(set) var tools: [MCPToolDefinition] = []

    /// System prompt prepended to every LLM request.
    public var systemPrompt: String?

    /// Maximum tool-use loop iterations per user message.
    public var maxToolIterations = 10

    // MARK: - Private State

    private let server: any MCPServer
    private let provider: any LLMProvider
    private var llmHistory: [LLMMessage] = []
    private var toolUIMap: [String: String] = [:]
    private var llmTools: [LLMTool] = []
    private var activeSessions: [String: ManualMCPAppSession] = [:]
    private var currentTask: Task<Void, Never>?

    /// Structured context awaiting injection on the next ``send(_:)`` call.
    /// Set by ``mergePendingContext(_:)``; consumed and cleared inside `send`.
    ///
    /// Rendered BindJS components call `host.updateModelContext({...})` to
    /// add selection or state information the model should see on the next
    /// turn. The update lands here; the next user message gets a
    /// `<context>…</context>` prefix visible only to the model, not the
    /// user's chat transcript.
    public private(set) var pendingContext: [String: JSONValue] = [:]

    // MARK: - Initialization

    /// Create an assistant with direct LLM access (BYOK mode).
    ///
    /// - Parameters:
    ///   - server: The MCP server to execute tools against (typically ``MCPAppsClient``).
    ///   - provider: The LLM provider (e.g., ``AnthropicProvider``).
    ///   - systemPrompt: Optional system prompt for the conversation.
    ///   - maxToolIterations: Maximum tool-use loop iterations per message.
    public init(
        server: any MCPServer,
        provider: any LLMProvider,
        systemPrompt: String? = nil,
        maxToolIterations: Int = 10
    ) {
        self.server = server
        self.provider = provider
        self.systemPrompt = systemPrompt
        self.maxToolIterations = maxToolIterations
    }

    /// Convenience initializer that creates an ``MCPAppsClient`` internally.
    ///
    /// - Parameters:
    ///   - serverURL: The MCP server endpoint URL.
    ///   - serverHeaders: HTTP headers for the MCP server (e.g., authorization).
    ///   - provider: The LLM provider.
    ///   - systemPrompt: Optional system prompt.
    public convenience init(
        serverURL: URL,
        serverHeaders: [String: String] = [:],
        provider: any LLMProvider,
        systemPrompt: String? = nil
    ) {
        let client = MCPAppsClient(url: serverURL, headers: serverHeaders)
        self.init(server: client, provider: provider, systemPrompt: systemPrompt)
    }

    // MARK: - Public API

    /// Discover tools from the MCP server.
    ///
    /// Called automatically when the first message is sent, but can be called
    /// manually to pre-load tools (e.g., during app launch).
    public func loadTools() async {
        do {
            let defs = try await server.listTools()
            let names = defs.map(\.name).joined(separator: ", ")
            log.info("Loaded \(defs.count, privacy: .public) tools: \(names, privacy: .public)")

            self.tools = defs
            self.toolUIMap = [:]
            self.llmTools = defs.map { def in
                if let uri = def.ui?.resourceUri {
                    toolUIMap[def.name] = uri
                }
                return LLMTool(
                    name: def.name,
                    description: def.description ?? "",
                    inputSchema: def.inputSchema ?? .object([:])
                )
            }
        } catch {
            log.error("Failed to load tools: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Send a user message and begin generating a response.
    ///
    /// The assistant streams the LLM response, executes any tool calls, renders
    /// interactive results via `MCPAppSession`, and continues the loop until
    /// the model stops. Progress is observable via ``conversation`` and ``isProcessing``.
    ///
    /// Calling `send` while already processing is a no-op.
    public func send(_ message: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else {
            log.info("send ignored (empty=\(text.isEmpty, privacy: .public) isProcessing=\(self.isProcessing, privacy: .public))")
            return
        }

        // User-visible bubble stays clean; the model sees any accumulated
        // component context prefixed to the same turn.
        conversation.append(.user(text: text))
        let contextKeys = pendingContext.keys.sorted().joined(separator: ",")
        let modelText = consumePendingContextPrefix().map { "\($0)\n\n\(text)" } ?? text
        log.info("send bytes=\(text.count, privacy: .public) contextKeys=\(contextKeys.isEmpty ? "<none>" : contextKeys, privacy: .public) llmHistoryBefore=\(self.llmHistory.count, privacy: .public)")
        llmHistory.append(.user(modelText))
        isProcessing = true
        activeSessions.removeAll()

        currentTask?.cancel()
        currentTask = Task {
            if tools.isEmpty {
                await loadTools()
            }

            defer { isProcessing = false }

            do {
                try await runConversationLoop()
            } catch is CancellationError {
                log.info("Conversation cancelled")
            } catch {
                log.error("Conversation failed: \(error)")
                conversation.append(.assistant(text: "Error: \(error.localizedDescription)"))
            }
        }
    }

    /// Cancel the current response generation.
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// Clear the conversation history and start fresh.
    ///
    /// Also cascades to ``LLMProvider/resetConversation()`` so providers
    /// that persist a server-side `conversationId` (e.g. the Metabind Agent
    /// proxy) drop it — otherwise the next ``send(_:)`` would re-submit
    /// under the previous, possibly poisoned, server conversation.
    public func reset() {
        cancel()
        conversation.clear()
        llmHistory.removeAll()
        activeSessions.removeAll()
        pendingContext.removeAll()
        _hostBridge = nil
        // Fire-and-forget — reset is synchronous from the UI's perspective,
        // and provider state is only consumed by the next send(), which
        // will be serialized after this task completes.
        let provider = self.provider
        Task { await provider.resetConversation() }
    }

    // MARK: - Pending Context

    /// Merge structured context into the pending-context buffer. The next
    /// ``send(_:)`` injects it as a `<context>…</context>` prefix visible
    /// to the model but not to the user's chat bubble.
    ///
    /// Typically called indirectly when a rendered BindJS component invokes
    /// `host.updateModelContext({...})`. Later merges replace matching keys.
    public func mergePendingContext(_ content: [String: JSONValue]) {
        for (key, value) in content {
            pendingContext[key] = value
        }
    }

    /// Convenience accepting loosely-typed input (e.g. from the JS bridge).
    public func mergePendingContext(_ content: [String: Any]) {
        guard case .object(let dict) = JSONValue.from(content) else { return }
        mergePendingContext(dict)
    }

    /// Drop any unsent pending context without sending. Useful when the
    /// assistant resets or the UI cancels a pending interaction.
    public func clearPendingContext() {
        pendingContext.removeAll()
    }

    private func consumePendingContextPrefix() -> String? {
        guard !pendingContext.isEmpty else { return nil }
        let payload: [String: Any] = pendingContext.mapValues { $0.toAny() }
        pendingContext.removeAll()
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]),
            let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return "<context>\n\(json)\n</context>"
    }

    // MARK: - Host Bridge

    private var _hostBridge: MetabindHostBridge?

    /// The ``MCPHostBridge`` exposed to rendered BindJS components via
    /// `useMCPHost()`. Lazily created on first access and wired to the
    /// assistant's internals (tool calls, message injection, context).
    ///
    /// SwiftUI-layer handlers (openLink, display mode, elicitation) are
    /// filled in by ``MetabindAssistantView`` when the assistant renders
    /// inside it. Apps that drive `MCPAppView` without the assistant view
    /// can set these handlers directly on `hostBridge.handlers`.
    public var hostBridge: MetabindHostBridge {
        if let _hostBridge { return _hostBridge }
        let bridge = MetabindHostBridge()
        bridge.handlers.toolCall = { [server] name, arguments in
            try await server.callToolUnwrapped(name: name, arguments: arguments)
        }
        bridge.handlers.onMessage = { [weak self] message in
            let text = message.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
                return nil
            }.joined(separator: "\n")
            self?.send(text)
        }
        bridge.handlers.onContext = { [weak self] context in
            guard case .object(let dict) = context.structuredContent ?? .null else { return }
            self?.mergePendingContext(dict)
        }
        _hostBridge = bridge
        return bridge
    }

    // MARK: - Conversation Loop

    private func runConversationLoop() async throws {
        let turnStart = Date()
        // Remote-loop providers (e.g. the Metabind Agent proxy) run the
        // full tool-call cycle server-side and emit `.toolResult` events
        // in-stream. One `streamResponse()` consumes the whole turn.
        if provider.runsToolsRemotely {
            log.info("turn start (remote-loop)")
            let (assistantText, toolCalls) = try await streamResponse()
            // Re-check after the suspension point: a reset() that interleaved
            // here has already cleared `llmHistory`, and appending the orphan
            // assistant turn (with its tool_use blocks) would poison the next
            // conversation — the agent service 400s client-supplied tool
            // protocol blocks.
            try Task.checkCancellation()
            llmHistory.append(.assistant(text: assistantText, toolCalls: toolCalls))
            let elapsed = Int(Date().timeIntervalSince(turnStart) * 1000)
            log.info("turn end (remote-loop) \(elapsed, privacy: .public)ms textBytes=\(assistantText?.count ?? 0, privacy: .public) toolCalls=\(toolCalls.count, privacy: .public)")
            return
        }
        log.info("turn start (local-loop, maxIter=\(self.maxToolIterations, privacy: .public))")
        defer {
            let elapsed = Int(Date().timeIntervalSince(turnStart) * 1000)
            log.info("turn end (local-loop) \(elapsed, privacy: .public)ms")
        }

        for iteration in 1...maxToolIterations {
            try Task.checkCancellation()
            log.info("Loop iteration \(iteration)")

            let (assistantText, toolCalls) = try await streamResponse()

            // Same orphan-append guard as the remote loop: reset() may have
            // cleared the history while streamResponse was suspended.
            try Task.checkCancellation()
            llmHistory.append(.assistant(text: assistantText, toolCalls: toolCalls))

            if toolCalls.isEmpty { return }

            var results: [LLMToolResult] = []

            for call in toolCalls {
                try Task.checkCancellation()

                let session = activeSessions[call.id]

                do {
                    log.info("Executing tool '\(call.name)'")
                    let result = try await server.callTool(
                        name: call.name,
                        arguments: call.arguments
                    )
                    session?.complete(with: result)

                    let resultText = result.content.compactMap {
                        if case .text(let t) = $0 { return t }
                        return nil
                    }.joined(separator: "\n")

                    results.append(LLMToolResult(
                        toolCallId: call.id,
                        content: resultText.isEmpty ? "Done" : resultText
                    ))
                } catch {
                    log.error("Tool '\(call.name)' failed: \(error)")
                    let errorResult = ToolResult(
                        text: "Error: \(error.localizedDescription)",
                        isError: true
                    )
                    session?.complete(with: errorResult)
                    results.append(LLMToolResult(
                        toolCallId: call.id,
                        content: "Error: \(error.localizedDescription)",
                        isError: true
                    ))
                }
            }

            llmHistory.append(.toolResults(results))

            if iteration == maxToolIterations {
                log.warning("Hit max tool iterations (\(self.maxToolIterations))")
            }
        }
    }

    // MARK: - Response Streaming

    private struct ToolAccumulator {
        let id: String
        let name: String
        var jsonFragment: String = ""
        /// Authoritative parsed args, when the provider sent a
        /// `toolCallArgumentsFinal` frame. Wins over `jsonFragment` parse
        /// because partials may be absent or non-concatenating in some
        /// provider paths (e.g. agent → OpenAI late-id).
        var canonicalArgs: JSONValue?

        var arguments: JSONValue {
            if let canonicalArgs { return canonicalArgs }
            guard let data = jsonFragment.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return .object([:]) }
            return JSONValue.from(obj)
        }

        /// True once usable arguments have arrived — either a canonical
        /// `toolCallArgumentsFinal` frame or a `jsonFragment` that parses to a
        /// JSON object. The end-of-stream sweep uses this to avoid shipping a
        /// tool call we only ever saw a `toolCallStart` for (e.g. the agent
        /// opened a tool block, then ended the turn without a terminal frame).
        var hasArguments: Bool {
            if canonicalArgs != nil { return true }
            guard let data = jsonFragment.data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
        }
    }

    private func streamResponse() async throws -> (
        text: String?,
        toolCalls: [LLMToolCall]
    ) {
        let stream = provider.stream(
            messages: llmHistory,
            tools: llmTools.isEmpty ? nil : llmTools,
            systemPrompt: systemPrompt
        )

        /// Accumulated text for the *current* assistant bubble only. Resets
        /// after each tool call so a new bubble opens for text emitted
        /// after the tool.
        var currentText = ""
        /// All assistant text across the turn, concatenated, for
        /// `llmHistory`. (The LLMMessage model collapses interleaved text
        /// into a single flat string; interleaving is preserved visually
        /// via the `conversation` messages instead.)
        var totalText = ""
        var textMessageId: String?
        var toolAccumulators: [Int: ToolAccumulator] = [:]
        var toolCalls: [LLMToolCall] = []

        for await event in stream {
            try Task.checkCancellation()

            switch event {
            case .textDelta(let delta):
                currentText += delta
                totalText += delta
                if let id = textMessageId {
                    conversation.updateAssistantText(id: id, text: currentText)
                } else {
                    let id = UUID().uuidString
                    textMessageId = id
                    conversation.append(.assistant(id: id, text: currentText))
                }

            case .toolCallStart(let index, let id, let name):
                let uiResource = toolUIMap[name]
                log.info("toolCallStart name=\(name, privacy: .public) id=\(id, privacy: .public) index=\(index, privacy: .public) uiResource=\(uiResource ?? "<none>", privacy: .public)")
                toolAccumulators[index] = ToolAccumulator(id: id, name: name)

                // Reset bubble state so text emitted *after* this tool
                // opens a fresh assistant bubble below the tool.
                currentText = ""
                textMessageId = nil

                let session = ManualMCPAppSession(
                    id: id,
                    toolName: name,
                    arguments: .object([:]),
                    resourceUri: uiResource,
                    server: server
                )
                activeSessions[id] = session
                conversation.append(.tool(session))

            case .toolCallArgumentDelta(let index, let fragment):
                guard toolAccumulators[index] != nil else {
                    log.warning("toolCallArgumentDelta for unknown index=\(index, privacy: .public); dropping")
                    break
                }
                toolAccumulators[index]?.jsonFragment += fragment

                // Feed a tolerant partial parse so the rendered tool UI fills in
                // as the model streams. The accumulated buffer is strict-valid
                // JSON only at the final fragment, so a strict parse would update
                // the view just once (at completion); PartialJSON.parse recovers
                // a valid JSONValue at most fragment boundaries. The authoritative
                // value still arrives via `toolCallArgumentsFinal`.
                if let acc = toolAccumulators[index],
                   let session = activeSessions[acc.id],
                   let partial = PartialJSON.parse(acc.jsonFragment) {
                    session.feed(partial)
                }

            case .toolCallArgumentsFinal(let index, let args):
                guard toolAccumulators[index] != nil else {
                    log.warning("toolCallArgumentsFinal for unknown index=\(index, privacy: .public); dropping")
                    break
                }
                toolAccumulators[index]?.canonicalArgs = args
                if let acc = toolAccumulators[index],
                   let session = activeSessions[acc.id] {
                    // Surface the canonical args to the live BindJS view —
                    // matters when partials were absent or didn't parse.
                    session.feed(args)
                }

            case .contentBlockStop(let index):
                if let acc = toolAccumulators[index] {
                    toolCalls.append(LLMToolCall(
                        id: acc.id,
                        name: acc.name,
                        arguments: acc.arguments
                    ))
                    log.info("toolCallComplete id=\(acc.id, privacy: .public) name=\(acc.name, privacy: .public) structure=\(Self.describeStructure(acc.arguments), privacy: .public)")
                    log.info("toolCallComplete id=\(acc.id, privacy: .public) args=\(Self.truncate(acc.jsonFragment, 1500), privacy: .public)")
                }

            case .done:
                for (_, acc) in toolAccumulators.sorted(by: { $0.key < $1.key }) {
                    guard !toolCalls.contains(where: { $0.id == acc.id }) else { continue }
                    guard acc.hasArguments else {
                        // `toolCallStart` opened a bubble but no arguments ever
                        // arrived (no terminal frame / contentBlockStop before
                        // the turn ended). Don't ship an empty-args tool call
                        // into history — a local loop would execute it — and
                        // surface the stranded bubble as failed instead of
                        // leaving it spinning.
                        log.warning("dropping incomplete tool call id=\(acc.id, privacy: .public) name=\(acc.name, privacy: .public) — toolCallStart with no arguments at end of stream")
                        activeSessions[acc.id]?.complete(with: ToolResult(
                            text: "Tool call did not complete",
                            isError: true
                        ))
                        continue
                    }
                    toolCalls.append(LLMToolCall(
                        id: acc.id,
                        name: acc.name,
                        arguments: acc.arguments
                    ))
                }
                // The agent signalled end-of-turn. Exit immediately instead
                // of waiting for the byte stream to close — the Metabind
                // agent proxy keeps the TCP connection open across turns,
                // so the `for await` would otherwise hang forever and
                // `isProcessing` would stay true.
                return (totalText.isEmpty ? nil : totalText, toolCalls)

            case .toolResult(let toolCallId, let content, _, let isError):
                // Remote loop: agent executed the tool and sent us the result.
                // Complete the rendering session; skip local `callTool`.
                // structuredContent is captured on the event but not yet
                // threaded through ToolResult — session rendering still
                // resolves its own BindJS resource URI.
                let preview = Self.truncate(content, 800)
                if isError {
                    log.error("toolResult id=\(toolCallId, privacy: .public) isError=true content=\(preview, privacy: .public)")
                } else {
                    log.info("toolResult id=\(toolCallId, privacy: .public) isError=false bytes=\(content.count, privacy: .public) preview=\(preview, privacy: .public)")
                }
                if activeSessions[toolCallId] == nil {
                    log.warning("toolResult id=\(toolCallId, privacy: .public) has no active session — dropping render")
                }
                if let session = activeSessions[toolCallId] {
                    let result = ToolResult(
                        text: content.isEmpty ? (isError ? "Error" : "Done") : content,
                        isError: isError
                    )
                    session.complete(with: result)
                }

            case .providerSwitch(let from, let to, let reason):
                log.info("Provider switched \(from) → \(to): \(reason)")

            case .error(let error):
                log.error("stream error: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }

        return (totalText.isEmpty ? nil : totalText, toolCalls)
    }

    // MARK: - Forensic logging helpers

    /// Trim a string to at most `max` characters for log output; appends
    /// `"…[n more]"` when truncated so the reader sees what was dropped.
    fileprivate static func truncate(_ s: String, _ max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + "…[\(s.count - max) more]"
    }

    /// Emit a one-line structural X-ray of a JSON value: for objects, the
    /// sorted keys; for arrays, the length and first element's shape. Drills
    /// one level to expose empties and mismatches without dumping the full
    /// payload. Intended for forensic logs — if the model passes
    /// `sections=[...]` with `content=[]`, this is where it shows.
    fileprivate static func describeStructure(_ value: JSONValue, depth: Int = 2) -> String {
        switch value {
        case .object(let dict):
            if depth == 0 { return "{\(dict.count)k}" }
            let pairs = dict.keys.sorted().map { key -> String in
                let inner = depth == 1 ? describeStructure(dict[key] ?? .null, depth: 0)
                                       : describeStructure(dict[key] ?? .null, depth: depth - 1)
                return "\(key)=\(inner)"
            }
            return "{\(pairs.joined(separator: ", "))}"
        case .array(let arr):
            guard let first = arr.first else { return "[]" }
            if depth == 0 { return "[\(arr.count)]" }
            return "[\(arr.count)×\(describeStructure(first, depth: depth - 1))]"
        case .string(let s):
            return "\"\(s.count)\""
        case .number(let n):
            return "n(\(n))"
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        }
    }
}
