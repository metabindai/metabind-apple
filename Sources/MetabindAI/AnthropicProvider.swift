import Foundation
import MCPAppsHost
import os

/// LLM provider for the Anthropic Messages API (Claude).
///
/// Streams responses using server-sent events. Supports tool use with
/// streaming argument deltas for progressive UI rendering.
///
/// ```swift
/// let provider = AnthropicProvider(apiKey: "sk-ant-...")
/// let assistant = MetabindAssistant(server: mcpClient, provider: provider)
/// ```
public struct AnthropicProvider: LLMProvider {
    public let apiKey: String
    public let model: String
    public let maxTokens: Int
    private let urlSession: URLSession

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let log = Logger(subsystem: "MetabindAssistant", category: "Anthropic")

    /// Create a provider for the Anthropic Messages API.
    ///
    /// - Parameters:
    ///   - apiKey: Your Anthropic API key.
    ///   - model: The model identifier.
    ///   - maxTokens: Maximum tokens in the response.
    ///   - urlSession: Transport, injectable for tests. Defaults to `.shared`.
    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-20250514",
        maxTokens: Int = 8192,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.urlSession = urlSession
    }

    public func stream(
        messages: [LLMMessage],
        tools: [LLMTool]?,
        systemPrompt: String?
    ) -> AsyncStream<LLMEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await performStream(
                        messages: messages,
                        tools: tools,
                        systemPrompt: systemPrompt,
                        continuation: continuation
                    )
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

    // MARK: - Streaming

    private func performStream(
        messages: [LLMMessage],
        tools: [LLMTool]?,
        systemPrompt: String?,
        continuation: AsyncStream<LLMEvent>.Continuation
    ) async throws {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": Self.encodeMessages(messages),
        ]
        if let systemPrompt, !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }
        if let tools, !tools.isEmpty {
            body["tools"] = Self.encodeTools(tools)
        }

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        Self.log.debug("Streaming: model=\(model), messages=\(messages.count)")

        let (bytes, response) = try await urlSession.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        guard http.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            Self.log.error("API error \(http.statusCode): \(errorBody)")

            if let data = errorBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AnthropicError.apiError(status: http.statusCode, message: message)
            }
            throw AnthropicError.apiError(status: http.statusCode, message: errorBody)
        }

        var currentEventType: String?
        var didComplete = false
        var finalStopReason: String?

        for try await line in bytes.lines {
            if Task.isCancelled { break }

            if line.hasPrefix("event: ") {
                currentEventType = String(line.dropFirst(7))
                continue
            }

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            switch currentEventType {
            case "content_block_start":
                if let cb = json["content_block"] as? [String: Any],
                   let type = cb["type"] as? String, type == "tool_use",
                   let id = cb["id"] as? String,
                   let name = cb["name"] as? String,
                   let index = json["index"] as? Int {
                    continuation.yield(.toolCallStart(index: index, id: id, name: name))
                }

            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any] {
                    if let text = delta["text"] as? String {
                        continuation.yield(.textDelta(text))
                    }
                    if let partial = delta["partial_json"] as? String {
                        if let index = json["index"] as? Int {
                            continuation.yield(.toolCallArgumentDelta(index: index, fragment: partial))
                        } else {
                            // Anthropic always tags content_block_delta with an
                            // integer `index`. If a gateway ever strips it we
                            // cannot route the fragment to the right
                            // accumulator — drop it loudly rather than silently
                            // mis-attributing it to another tool block.
                            Self.log.warning("content_block_delta has partial_json but no integer index; dropping fragment")
                        }
                    }
                }

            case "content_block_stop":
                if let index = json["index"] as? Int {
                    continuation.yield(.contentBlockStop(index: index))
                }

            case "message_delta":
                if let delta = json["delta"] as? [String: Any] {
                    finalStopReason = delta["stop_reason"] as? String
                }

            case "message_stop":
                didComplete = true
                continuation.yield(.done(stopReason: Self.parseStopReason(finalStopReason)))

            case "error":
                let msg = (json["error"] as? [String: Any])?["message"] as? String
                    ?? "Unknown stream error"
                Self.log.error("Stream error: \(msg)")
                continuation.yield(.error(AnthropicError.apiError(status: 0, message: msg)))

            default:
                break
            }
        }

        if !didComplete {
            Self.log.warning("Stream ended without message_stop")
            continuation.yield(.done(stopReason: Self.parseStopReason(finalStopReason)))
        }
    }

    // MARK: - Encoding

    private static func encodeMessages(_ messages: [LLMMessage]) -> [[String: Any]] {
        messages.map { msg in
            switch msg {
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
                    if result.isError {
                        block["is_error"] = true
                    }
                    return block
                }
                return ["role": "user", "content": blocks]
            }
        }
    }

    private static func encodeTools(_ tools: [LLMTool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema.toAny(),
            ]
        }
    }

    private static func parseStopReason(_ raw: String?) -> LLMStopReason {
        switch raw {
        case "end_turn": .endTurn
        case "tool_use": .toolUse
        case "max_tokens": .maxTokens
        case let s?: .unknown(s)
        case nil: .endTurn
        }
    }
}

/// Errors from the Anthropic Messages API.
public enum AnthropicError: Error, LocalizedError, Sendable {
    case invalidResponse
    case apiError(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Anthropic API"
        case .apiError(let status, let message): "Anthropic API error \(status): \(message)"
        }
    }
}
