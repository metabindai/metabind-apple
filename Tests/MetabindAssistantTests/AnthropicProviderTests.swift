import Testing
import Foundation
@testable import MetabindAssistant
@testable import MCPAppsHost

/// Minimal, capture-free URL stub dedicated to this suite. The shared
/// `MockURLProtocol` keeps a single process-global handler, so a second suite
/// using it would race the agent suite across parallel test execution. This
/// stub has its own state and the suite is `.serialized`, so its two tests
/// never collide with each other or with any other suite.
private final class MockAnthropicURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var sseBody = Data()
    private static let lock = NSLock()

    static func install(sse: String) -> URLSession {
        lock.lock(); sseBody = Data(sse.utf8); lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAnthropicURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockAnthropicURLProtocol.lock.lock()
        let body = MockAnthropicURLProtocol.sseBody
        MockAnthropicURLProtocol.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("AnthropicProvider SSE parsing", .serialized)
struct AnthropicProviderTests {

    private func makeProvider(sse: String) -> AnthropicProvider {
        AnthropicProvider(apiKey: "sk-ant-test", urlSession: MockAnthropicURLProtocol.install(sse: sse))
    }

    private func collect(_ stream: AsyncStream<LLMEvent>) async -> [LLMEvent] {
        var events: [LLMEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    /// Happy path: a tool_use block streams `input_json_delta` fragments, each
    /// tagged with the content-block `index`. The provider must plumb that
    /// index through `toolCallArgumentDelta` so the assistant routes the
    /// fragment to the matching accumulator — not to "the latest open block."
    @Test func contentBlockDeltaCarriesBlockIndex() async {
        // The tool_use block is at content index 1 (a text block precedes it),
        // so a correct index is observable: 1, not 0.
        let sse = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1"}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Let me check. "}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"getWeather"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"city\\":"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\\"NYC\\"}"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":1}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("weather?")], tools: nil, systemPrompt: nil
        ))

        // toolCallStart for the tool block must carry index 1.
        let starts = events.compactMap { event -> (Int, String, String)? in
            if case .toolCallStart(let i, let id, let name) = event { return (i, id, name) }
            return nil
        }
        #expect(starts.count == 1)
        #expect(starts.first?.0 == 1)
        #expect(starts.first?.1 == "toolu_1")

        // Both partials route to index 1, in order, verbatim. Concatenation
        // parses to the canonical input.
        let deltas = events.compactMap { event -> (Int, String)? in
            if case .toolCallArgumentDelta(let i, let s) = event { return (i, s) }
            return nil
        }
        #expect(deltas.map(\.0) == [1, 1])
        let concatenated = deltas.map(\.1).joined()
        let parsed = try? JSONSerialization.jsonObject(with: Data(concatenated.utf8)) as? [String: String]
        #expect(parsed == ["city": "NYC"])

        // contentBlockStop is emitted for both blocks.
        let stops = events.compactMap { event -> Int? in
            if case .contentBlockStop(let i) = event { return i }
            return nil
        }
        #expect(stops == [0, 1])
    }

    /// Defensive: if a `content_block_delta` ever arrives carrying `partial_json`
    /// but no integer `index` (a gateway stripping it, an API change), the
    /// fragment must be DROPPED — not forwarded with a guessed index, which the
    /// index-routing assistant would mis-attribute. The provider logs a warning
    /// and emits no `toolCallArgumentDelta`; this pins that contract.
    @Test func partialJsonWithoutIndexIsDropped() async {
        let sse = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1"}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"getWeather"}}

        event: content_block_delta
        data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\\"city\\":\\"NYC\\"}"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("weather?")], tools: nil, systemPrompt: nil
        ))

        // The malformed (index-less) partial must not surface as an arg delta.
        let deltas = events.filter {
            if case .toolCallArgumentDelta = $0 { true } else { false }
        }
        #expect(deltas.isEmpty, "index-less partial_json must be dropped, not forwarded")

        // The tool block itself still opened.
        let starts = events.filter { if case .toolCallStart = $0 { true } else { false } }
        #expect(starts.count == 1)
    }
}
