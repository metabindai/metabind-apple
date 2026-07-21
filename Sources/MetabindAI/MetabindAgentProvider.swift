import Foundation
import MCPAppsHost
import os

/// LLM provider backed by the Metabind Agent proxy (`agent.metabind.ai`).
///
/// The proxy holds the upstream LLM credentials server-side, fetches the
/// project's published MCP tools, runs the tool-call loop, and streams
/// normalized events back over SSE. SDK clients authenticate with the
/// project-scoped Metabind API key — no provider keys in the app binary.
///
/// ```swift
/// let provider = MetabindAgentProvider(
///     apiKey: metabindApiKey,
///     orgId: "org_abc",
///     projectId: "proj_xyz"
/// )
/// let assistant = MetabindAssistant(server: mcpClient, provider: provider)
/// ```
///
/// See `metabind-agent/docs/sdk-guide.md` for the full event/error contract.
public actor MetabindAgentProvider: LLMProvider {

    public static let productionHost = URL(string: "https://agent.metabind.ai")!
    public static let developmentHost = URL(string: "https://agent-dev.metabind.ai")!

    public nonisolated let baseURL: URL
    public nonisolated let apiKey: String
    public nonisolated let orgId: String
    public nonisolated let projectId: String
    private nonisolated let urlSession: URLSession

    private static let log = Logger(subsystem: "MetabindAssistant", category: "AgentProxy")

    /// Server-assigned after the first `message_start`; echoed on subsequent
    /// turns so the proxy merges history against its Redis-stored record.
    private var conversationId: String?

    /// Per-turn state for tool-use index allocation and id→index resolution.
    /// Lives inside `run(...)` so a turn that ends via error, cancellation,
    /// or a non-tool_use stop after `tool_use_start` cannot leak stale ids
    /// into the next turn — where a coincidentally reused id would route
    /// a partial to an accumulator the assistant never opened.
    private struct TurnState {
        var toolIndexCounter: Int = 0
        var toolUseIndexById: [String: Int] = [:]
    }

    public init(
        baseURL: URL = MetabindAgentProvider.productionHost,
        apiKey: String,
        orgId: String,
        projectId: String,
        conversationId: String? = nil,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.orgId = orgId
        self.projectId = projectId
        self.conversationId = conversationId
        self.urlSession = urlSession
    }

    public nonisolated var runsToolsRemotely: Bool { true }

    /// The current conversation id, if a turn has completed. Exposed so
    /// callers can persist it between app launches and resume later.
    public var currentConversationId: String? {
        conversationId
    }

    /// Drop the stored conversation id so the next turn starts fresh.
    /// (Per-turn tool-index state lives inside `run(...)` and resets
    /// automatically; nothing actor-scoped to clear there.)
    public func resetConversation() async {
        conversationId = nil
    }

    // MARK: - LLMProvider

    public nonisolated func stream(
        messages: [LLMMessage],
        tools: [LLMTool]?,
        systemPrompt: String?
    ) -> AsyncStream<LLMEvent> {
        // `tools` and `systemPrompt` are ignored — both live server-side in
        // `settings.mcp.tools` and `settings.agent.systemPrompt` and are
        // attached by the agent service.
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await self.run(messages: messages, continuation: continuation)
                } catch is CancellationError {
                    // Client-initiated cancel — stream was already finished.
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.error(error))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request / response pipeline

    private func run(
        messages: [LLMMessage],
        continuation: AsyncStream<LLMEvent>.Continuation
    ) async throws {
        let url = baseURL
            .appendingPathComponent(orgId)
            .appendingPathComponent(projectId)
            .appendingPathComponent("chat")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "messages": try scopedMessages(messages),
            "stream": true,
        ]
        if let conversationId {
            body["conversationId"] = conversationId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.log.debug("POST /chat orgId=\(self.orgId, privacy: .public) conversationId=\(self.conversationId ?? "<new>", privacy: .public)")

        let (bytes, response) = try await urlSession.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AgentError.invalidResponse
        }
        if http.statusCode != 200 {
            let err = try await readHttpError(status: http.statusCode, bytes: bytes)
            Self.log.error("Agent HTTP \(http.statusCode, privacy: .public): \(err.localizedDescription, privacy: .public)")
            throw err
        }

        // `URLSession.AsyncBytes.lines` collapses blank lines, so we can't
        // use the blank-line terminator that the SSE spec prescribes.
        // Instead, flush the pending frame on the next `event:` line or at
        // end-of-stream. Heartbeats (`:` comments) are skipped.
        var pendingEvent: String?
        var pendingData = ""
        var turnState = TurnState()

        for try await line in bytes.lines {
            try Task.checkCancellation()

            if line.hasPrefix(":") { continue } // heartbeat / comment

            if line.hasPrefix("event:") {
                if let name = pendingEvent {
                    let terminal = handleFrame(
                        name: name,
                        data: pendingData,
                        state: &turnState,
                        continuation: continuation
                    )
                    if terminal { return }
                }
                pendingEvent = String(line.dropFirst("event:".count))
                    .trimmingCharacters(in: .whitespaces)
                pendingData = ""
            } else if line.hasPrefix("data:") {
                let payload = String(line.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces)
                pendingData = pendingData.isEmpty ? payload : pendingData + "\n" + payload
            }
        }

        if let name = pendingEvent {
            _ = handleFrame(name: name, data: pendingData, state: &turnState, continuation: continuation)
        }
    }

    /// Returns `true` if the frame terminates the stream.
    private func handleFrame(
        name: String,
        data: String,
        state: inout TurnState,
        continuation: AsyncStream<LLMEvent>.Continuation
    ) -> Bool {
        guard let bytes = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        else {
            Self.log.warning("Dropped malformed SSE frame (event=\(name, privacy: .public))")
            return false
        }

        switch name {
        case "message_start":
            if let id = json["conversationId"] as? String {
                conversationId = id
                Self.log.info("SSE message_start conversationId=\(id, privacy: .public)")
            }
            return false

        case "text_delta":
            if let text = json["text"] as? String {
                continuation.yield(.textDelta(text))
            }
            return false

        case "tool_use_start":
            guard let id = json["id"] as? String,
                  let toolName = json["name"] as? String else {
                Self.log.warning("SSE tool_use_start missing id/name: \(data, privacy: .public)")
                return false
            }
            let index = state.toolIndexCounter
            state.toolIndexCounter += 1
            state.toolUseIndexById[id] = index
            Self.log.info("SSE tool_use_start name=\(toolName, privacy: .public) id=\(id, privacy: .public) index=\(index, privacy: .public)")
            continuation.yield(.toolCallStart(index: index, id: id, name: toolName))
            return false

        case "tool_use_input_partial":
            guard let id = json["id"] as? String,
                  let partial = json["partialInput"] as? String else {
                Self.log.warning("SSE tool_use_input_partial missing id/partialInput: \(data, privacy: .public)")
                return false
            }
            guard let index = state.toolUseIndexById[id] else {
                // No matching tool_use_start. Protocol violation by the
                // agent — drop the fragment rather than routing to the
                // "latest" tool, which would mis-attribute it under
                // id-tagged interleaving.
                Self.log.warning("SSE tool_use_input_partial for unknown id=\(id, privacy: .public); dropping")
                return false
            }
            Self.log.debug("SSE tool_use_input_partial id=\(id, privacy: .public) index=\(index, privacy: .public) bytes=\(partial.count, privacy: .public)")
            continuation.yield(.toolCallArgumentDelta(index: index, fragment: partial))
            return false

        case "tool_use":
            guard let id = json["id"] as? String,
                  let toolName = json["name"] as? String else {
                Self.log.warning("SSE tool_use missing id/name: \(data, privacy: .public)")
                return false
            }
            let input = json["input"] ?? [String: Any]()
            let canonical = JSONValue.from(input)
            let inputJson = (try? JSONSerialization.data(withJSONObject: input))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "<unencodable>"

            if let index = state.toolUseIndexById.removeValue(forKey: id) {
                // Streaming path: tool_use_start + 0..N tool_use_input_partial
                // already ran. The terminal `input` is authoritative — emit
                // it as `toolCallArgumentsFinal` so the assistant uses it
                // even when partials were absent or didn't concatenate
                // (e.g. agent → OpenAI late-id case).
                Self.log.info("SSE tool_use (terminal) name=\(toolName, privacy: .public) id=\(id, privacy: .public) index=\(index, privacy: .public) bytes=\(inputJson.count, privacy: .public)")
                continuation.yield(.toolCallArgumentsFinal(index: index, arguments: canonical))
                continuation.yield(.contentBlockStop(index: index))
            } else {
                // Legacy path: older agent / non-streaming provider emitted
                // only the terminal `tool_use`. Synthesize Start/Final/Stop
                // so the bubble renders identically.
                let index = state.toolIndexCounter
                state.toolIndexCounter += 1
                Self.log.info("SSE tool_use (one-shot) name=\(toolName, privacy: .public) id=\(id, privacy: .public) index=\(index, privacy: .public) bytes=\(inputJson.count, privacy: .public)")
                Self.log.info("SSE tool_use input id=\(id, privacy: .public) input=\(Self.truncate(inputJson, 1500), privacy: .public)")
                continuation.yield(.toolCallStart(index: index, id: id, name: toolName))
                continuation.yield(.toolCallArgumentsFinal(index: index, arguments: canonical))
                continuation.yield(.contentBlockStop(index: index))
            }
            return false

        case "tool_result":
            guard let toolUseId = json["toolUseId"] as? String else {
                Self.log.warning("SSE tool_result missing toolUseId: \(data, privacy: .public)")
                return false
            }
            let isError = json["isError"] as? Bool ?? false
            let text = Self.flatten(mcpContent: json["content"])
            let structured = json["structuredContent"].map { JSONValue.from($0) }
            if isError {
                Self.log.error("SSE tool_result toolUseId=\(toolUseId, privacy: .public) isError=true content=\(Self.truncate(text, 1000), privacy: .public)")
            } else {
                Self.log.info("SSE tool_result toolUseId=\(toolUseId, privacy: .public) isError=false bytes=\(text.count, privacy: .public) preview=\(Self.truncate(text, 800), privacy: .public)")
            }
            continuation.yield(.toolResult(
                toolCallId: toolUseId,
                content: text,
                structuredContent: structured,
                isError: isError
            ))
            return false

        case "provider_switch":
            let from = json["from"] as? String ?? ""
            let to = json["to"] as? String ?? ""
            let reason = json["reason"] as? String ?? ""
            Self.log.info("SSE provider_switch \(from, privacy: .public) → \(to, privacy: .public) (\(reason, privacy: .public))")
            continuation.yield(.providerSwitch(from: from, to: to, reason: reason))
            return false

        case "message_stop":
            let raw = json["stopReason"] as? String ?? "unknown"
            Self.log.info("SSE message_stop stopReason=\(raw, privacy: .public)")
            let stop: LLMStopReason = switch raw {
            case "end_turn": .endTurn
            case "tool_use": .toolUse
            case "max_tokens": .maxTokens
            default: .unknown(raw)
            }
            // `tool_use` is emitted between provider turns while the agent
            // executes a tool server-side — the stream continues.
            if stop == .toolUse { return false }
            continuation.yield(.done(stopReason: stop))
            return true

        case "error":
            let code = json["code"] as? String ?? "unknown"
            let message = json["message"] as? String ?? ""
            Self.log.error("SSE error code=\(code, privacy: .public) message=\(message, privacy: .public)")
            continuation.yield(.error(AgentError.serverError(code: code, message: message)))
            return true

        default:
            Self.log.debug("Unhandled SSE event '\(name, privacy: .public)' data=\(Self.truncate(data, 200), privacy: .public)")
            return false
        }
    }

    // MARK: - Message translation

    /// On a resumed conversation, only the newest user turn is sent; the
    /// server merges it with persisted history. On a fresh conversation, the
    /// full history is included — minus tool protocol blocks, which the agent
    /// service manages itself and rejects with `bad_request` when supplied by
    /// the client. Replayed assistant turns keep their text; tool-only turns
    /// and tool results are dropped.
    func scopedMessages(_ messages: [LLMMessage]) throws -> [[String: Any]] {
        let scoped: [LLMMessage]
        if conversationId != nil {
            if let idx = messages.lastIndex(where: { if case .user = $0 { true } else { false } }) {
                scoped = [messages[idx]]
            } else {
                scoped = []
            }
        } else {
            scoped = messages.compactMap { message in
                switch message {
                case .user:
                    return message
                case .assistant(let text, _):
                    guard let text, !text.isEmpty else { return nil }
                    return .assistant(text: text, toolCalls: [])
                case .toolResults:
                    return nil
                }
            }
        }
        return scoped.map(Self.encode)
    }

    private static func encode(_ message: LLMMessage) -> [String: Any] {
        switch message {
        case .user(let text):
            return ["role": "user", "content": text]

        case .assistant(let text, let toolCalls):
            var blocks: [[String: Any]] = []
            if let text, !text.isEmpty {
                blocks.append(["type": "text", "text": text])
            }
            for call in toolCalls {
                blocks.append([
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.name,
                    "input": call.arguments.toAny(),
                ])
            }
            return ["role": "assistant", "content": blocks]

        case .toolResults(let results):
            let blocks: [[String: Any]] = results.map { result in
                var block: [String: Any] = [
                    "type": "tool_result",
                    "tool_use_id": result.toolCallId,
                    "content": result.content,
                ]
                if result.isError { block["is_error"] = true }
                return block
            }
            return ["role": "user", "content": blocks]
        }
    }

    private static func truncate(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n)) + "…"
    }

    /// MCP content arrays come through as `[{type:"text", text:"..."}]` — flatten to plain text.
    private static func flatten(mcpContent: Any?) -> String {
        guard let blocks = mcpContent as? [[String: Any]] else {
            if let s = mcpContent as? String { return s }
            return ""
        }
        return blocks.compactMap { block -> String? in
            guard (block["type"] as? String) == "text" else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n")
    }

    // MARK: - Error body parsing

    private func readHttpError(
        status: Int,
        bytes: URLSession.AsyncBytes
    ) async throws -> AgentError {
        var buffer = ""
        do {
            for try await line in bytes.lines {
                buffer += line + "\n"
                if buffer.count > 16 * 1024 { break }
            }
        } catch {
            // Fall through with what we have.
        }
        if let data = buffer.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["error"] as? String,
           let message = json["message"] as? String {
            return .serverError(code: code, message: message)
        }
        return .httpStatus(status, buffer.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Errors

public enum AgentError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int, String)
    case serverError(code: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from agent service"
        case .httpStatus(let s, let body): "Agent HTTP \(s): \(body)"
        case .serverError(let code, let message): "\(code): \(message)"
        }
    }
}
