import Testing
import Foundation
@testable import MetabindAssistant
@testable import MCPAppsHost

@Suite("MetabindAgentProvider", .serialized)
struct MetabindAgentProviderTests {

    // MARK: - Helpers

    private static let baseURL = URL(string: "https://agent-test.example.com")!

    private func makeProvider(
        sse: String,
        status: Int = 200,
        conversationId: String? = nil
    ) -> MetabindAgentProvider {
        let session = MockURLProtocol.install { _ in .sse(sse, status: status) }
        return MetabindAgentProvider(
            baseURL: Self.baseURL,
            apiKey: "test-api-key",
            orgId: "org_abc",
            projectId: "proj_xyz",
            conversationId: conversationId,
            urlSession: session
        )
    }

    private func makeProvider(
        response: MockURLProtocol.Response,
        conversationId: String? = nil
    ) -> MetabindAgentProvider {
        let session = MockURLProtocol.install { _ in response }
        return MetabindAgentProvider(
            baseURL: Self.baseURL,
            apiKey: "test-api-key",
            orgId: "org_abc",
            projectId: "proj_xyz",
            conversationId: conversationId,
            urlSession: session
        )
    }

    private func collect(_ stream: AsyncStream<LLMEvent>) async -> [LLMEvent] {
        var events: [LLMEvent] = []
        for await e in stream { events.append(e) }
        return events
    }

    /// Thread-safe call counter for multi-response MockURLProtocol handlers.
    private final class TurnCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            let v = n; n += 1; return v
        }
    }

    // MARK: - Request shape

    @Test func buildsExpectedRequest() async throws {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let provider = makeProvider(sse: sse)

        _ = await collect(provider.stream(
            messages: [.user("hi")], tools: nil, systemPrompt: nil
        ))

        let request = try #require(MockURLProtocol.capturedRequest())
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://agent-test.example.com/org_abc/proj_xyz/chat")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")

        let body = try #require(MockURLProtocol.capturedBody())
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["stream"] as? Bool == true)
        #expect(json["conversationId"] == nil) // no conversationId on first call
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["content"] as? String == "hi")
    }

    // MARK: - Event translation

    @Test func textDeltaEmitsTextDelta() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: text_delta
        data: {"text":"Hello, "}

        event: text_delta
        data: {"text":"world"}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("hi")], tools: nil, systemPrompt: nil
        ))

        let texts = events.compactMap { event -> String? in
            if case .textDelta(let t) = event { return t }
            return nil
        }
        #expect(texts == ["Hello, ", "world"])
    }

    @Test func toolUseSynthesizesStartArgsFinalAndStop() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_use
        data: {"id":"toolu_1","name":"getWeather","input":{"city":"NYC"}}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("weather?")], tools: nil, systemPrompt: nil
        ))

        // Expect: toolCallStart, toolCallArgumentsFinal, contentBlockStop, done
        #expect(events.count == 4)
        if case .toolCallStart(let index, let id, let name) = events[0] {
            #expect(index == 0)
            #expect(id == "toolu_1")
            #expect(name == "getWeather")
        } else {
            Issue.record("expected .toolCallStart, got \(events[0])")
        }
        if case .toolCallArgumentsFinal(let index, let args) = events[1] {
            #expect(index == 0)
            #expect(args == .object(["city": .string("NYC")]))
        } else {
            Issue.record("expected .toolCallArgumentsFinal, got \(events[1])")
        }
        if case .contentBlockStop(let index) = events[2] {
            #expect(index == 0)
        } else {
            Issue.record("expected .contentBlockStop, got \(events[2])")
        }
    }

    @Test func streamingToolUseEmitsStartPartialsAndStop() async {
        defer { MockURLProtocol.uninstall() }
        // MET-1197: the agent now forwards Anthropic's content_block_delta
        // stream as `tool_use_start` + N× `tool_use_input_partial` +
        // terminal `tool_use`. Concatenated partials must parse to the
        // canonical input post-stop, per the Anthropic streaming contract.
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_use_start
        data: {"id":"toolu_1","name":"search"}

        event: tool_use_input_partial
        data: {"id":"toolu_1","partialInput":"{\\"q\\":\\""}

        event: tool_use_input_partial
        data: {"id":"toolu_1","partialInput":"shoes"}

        event: tool_use_input_partial
        data: {"id":"toolu_1","partialInput":"\\"}"}

        event: tool_use
        data: {"id":"toolu_1","name":"search","input":{"q":"shoes"}}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("find shoes")], tools: nil, systemPrompt: nil
        ))

        // Expect: toolCallStart, 3× toolCallArgumentDelta, toolCallArgumentsFinal, contentBlockStop, done
        #expect(events.count == 7)

        if case .toolCallStart(let index, let id, let name) = events[0] {
            #expect(index == 0)
            #expect(id == "toolu_1")
            #expect(name == "search")
        } else {
            Issue.record("expected .toolCallStart, got \(events[0])")
        }

        // Partial fragments are forwarded verbatim — not cumulative — and
        // each carries the correct accumulator index.
        let partials = events[1...3].compactMap { event -> (Int, String)? in
            if case .toolCallArgumentDelta(let i, let s) = event { return (i, s) }
            return nil
        }
        #expect(partials.map(\.0) == [0, 0, 0])
        #expect(partials.map(\.1) == [#"{"q":""#, "shoes", #""}"#])
        // Concatenation parses to the canonical object (Anthropic contract).
        let concatenated = partials.map(\.1).joined()
        let parsed = try? JSONSerialization.jsonObject(with: Data(concatenated.utf8)) as? [String: String]
        #expect(parsed == ["q": "shoes"])

        // The terminal `tool_use` emits ArgumentsFinal with the canonical
        // parsed input — authoritative, used by the assistant even when
        // partials don't concatenate cleanly.
        if case .toolCallArgumentsFinal(let index, let args) = events[4] {
            #expect(index == 0)
            #expect(args == .object(["q": .string("shoes")]))
        } else {
            Issue.record("expected .toolCallArgumentsFinal, got \(events[4])")
        }

        if case .contentBlockStop(let index) = events[5] {
            #expect(index == 0)
        } else {
            Issue.record("expected .contentBlockStop, got \(events[5])")
        }

        // The terminal `tool_use` must NOT re-emit toolCallStart — that
        // would duplicate the bubble in the assistant UI.
        let starts = events.filter { if case .toolCallStart = $0 { true } else { false } }
        #expect(starts.count == 1)
    }

    @Test func twoStreamingToolCallsGetSeparateIndices() async {
        defer { MockURLProtocol.uninstall() }
        // Anthropic guarantees content blocks don't interleave, but the
        // agent may emit two tool calls in the same turn (parallel-friendly
        // models). Each gets its own index; ids don't collide.
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_use_start
        data: {"id":"toolu_a","name":"search"}

        event: tool_use_input_partial
        data: {"id":"toolu_a","partialInput":"{\\"q\\":\\"a\\"}"}

        event: tool_use
        data: {"id":"toolu_a","name":"search","input":{"q":"a"}}

        event: tool_use_start
        data: {"id":"toolu_b","name":"search"}

        event: tool_use_input_partial
        data: {"id":"toolu_b","partialInput":"{\\"q\\":\\"b\\"}"}

        event: tool_use
        data: {"id":"toolu_b","name":"search","input":{"q":"b"}}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("two")], tools: nil, systemPrompt: nil
        ))

        let starts = events.compactMap { event -> (Int, String)? in
            if case .toolCallStart(let i, let id, _) = event { return (i, id) }
            return nil
        }
        #expect(starts.count == 2)
        #expect(starts[0].0 == 0)
        #expect(starts[0].1 == "toolu_a")
        #expect(starts[1].0 == 1)
        #expect(starts[1].1 == "toolu_b")

        let stops = events.compactMap { event -> Int? in
            if case .contentBlockStop(let i) = event { return i }
            return nil
        }
        #expect(stops == [0, 1])
    }

    @Test func legacyTerminalOnlyToolUseFallsBackToOneShot() async {
        defer { MockURLProtocol.uninstall() }
        // Older agent build, or a provider that buffers server-side (per
        // tool-input-streaming.test.ts, Google's path), emits only the
        // terminal `tool_use` with no start/partial events. We synthesize
        // Start/ArgumentsFinal/Stop so the assistant sees a complete bubble.
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_use
        data: {"id":"toolu_legacy","name":"getWeather","input":{"city":"NYC"}}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("weather?")], tools: nil, systemPrompt: nil
        ))

        #expect(events.count == 4)
        if case .toolCallStart(let index, let id, _) = events[0] {
            #expect(index == 0)
            #expect(id == "toolu_legacy")
        } else {
            Issue.record("expected .toolCallStart, got \(events[0])")
        }
        if case .toolCallArgumentsFinal(let index, let args) = events[1] {
            #expect(index == 0)
            #expect(args == .object(["city": .string("NYC")]))
        } else {
            Issue.record("expected .toolCallArgumentsFinal, got \(events[1])")
        }
        if case .contentBlockStop = events[2] {} else {
            Issue.record("expected .contentBlockStop, got \(events[2])")
        }
    }

    @Test func streamingToolUseWithoutPartialsStillCarriesCanonicalArgs() async {
        defer { MockURLProtocol.uninstall() }
        // The provider-agnostic agent contract allows 0..N
        // `tool_use_input_partial` events between `tool_use_start` and
        // `tool_use`. When N=0 — possible for very small inputs, the
        // agent's Google synthetic-stream path under certain conditions,
        // or any future provider that omits per-chunk forwarding — the
        // terminal `tool_use.input` is the only source of canonical args.
        // We must surface it via `toolCallArgumentsFinal`; otherwise the
        // assistant accumulator parses an empty buffer and the tool call
        // ships with `{}`.
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_use_start
        data: {"id":"toolu_z","name":"ping"}

        event: tool_use
        data: {"id":"toolu_z","name":"ping","input":{"host":"example.com","timeoutMs":500}}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("ping")], tools: nil, systemPrompt: nil
        ))

        // No partials at all. Sequence: start → argumentsFinal → stop → done.
        #expect(events.count == 4)
        let partialCount = events.filter {
            if case .toolCallArgumentDelta = $0 { true } else { false }
        }.count
        #expect(partialCount == 0)
        if case .toolCallArgumentsFinal(let index, let args) = events[1] {
            #expect(index == 0)
            #expect(args == .object([
                "host": .string("example.com"),
                "timeoutMs": .number(500),
            ]))
        } else {
            Issue.record("expected .toolCallArgumentsFinal, got \(events[1])")
        }
    }

    @Test func interleavedPartialsRouteByIdNotByLatestIndex() async {
        defer { MockURLProtocol.uninstall() }
        // The agent's cross-provider contract is id-tagged: nothing in
        // `tool-input-streaming.test.ts` guarantees the proxy will keep
        // partials for two open tool blocks strictly sequential. If a
        // future provider (or a network reorder via the SSE buffer) lands
        // a partial for tool A *after* tool B has started, the iOS
        // provider must still attribute it to A via its index — not to
        // whichever block opened last. This test pins index-routing.
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_use_start
        data: {"id":"toolu_a","name":"search"}

        event: tool_use_input_partial
        data: {"id":"toolu_a","partialInput":"{\\"q\\":\\"a"}

        event: tool_use_start
        data: {"id":"toolu_b","name":"search"}

        event: tool_use_input_partial
        data: {"id":"toolu_b","partialInput":"{\\"q\\":\\"b\\"}"}

        event: tool_use_input_partial
        data: {"id":"toolu_a","partialInput":"\\"}"}

        event: tool_use
        data: {"id":"toolu_b","name":"search","input":{"q":"b"}}

        event: tool_use
        data: {"id":"toolu_a","name":"search","input":{"q":"a"}}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("two")], tools: nil, systemPrompt: nil
        ))

        // For each tool, collect deltas in arrival order with their index.
        let deltasByIndex: [(Int, String)] = events.compactMap { event in
            if case .toolCallArgumentDelta(let i, let s) = event { return (i, s) }
            return nil
        }
        // Expected:
        //   index 0 (toolu_a): "{\"q\":\"a", "\"}"   → concat → {"q":"a"}
        //   index 1 (toolu_b): "{\"q\":\"b\"}"       → already valid
        let a = deltasByIndex.filter { $0.0 == 0 }.map(\.1).joined()
        let b = deltasByIndex.filter { $0.0 == 1 }.map(\.1).joined()
        let parsedA = try? JSONSerialization.jsonObject(with: Data(a.utf8)) as? [String: String]
        let parsedB = try? JSONSerialization.jsonObject(with: Data(b.utf8)) as? [String: String]
        #expect(parsedA == ["q": "a"])
        #expect(parsedB == ["q": "b"])

        // Crucially: the partial that arrived *after* tool B opened —
        // tagged `toolu_a` — must route to index 0, not index 1. If the
        // old "latest index" routing were still in effect, index 1 would
        // see the trailing `"}` fragment and parse to `{"q":"b"}"}` (invalid).
        let aDeltas = deltasByIndex.filter { $0.0 == 0 }.map(\.1)
        #expect(aDeltas.contains(#""}"#))
        let bDeltas = deltasByIndex.filter { $0.0 == 1 }.map(\.1)
        #expect(!bDeltas.contains(#""}"#))
    }

    @Test func turnStateDoesNotLeakAcrossStreamInvocations() async {
        defer { MockURLProtocol.uninstall() }
        // Turn 1 opens `tool_use_start` for toolu_x then terminates via
        // an `error` event before the terminal `tool_use` lands — i.e. the
        // id stays unresolved. If the provider held this state at the
        // actor level, turn 2 would either start at index 1 (counter
        // leak) or find a pre-seeded id mapping for toolu_x (map leak).
        // Both must not happen — per-turn state lives only within
        // `run(...)`.

        let turn1SSE = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_use_start
        data: {"id":"toolu_x","name":"search"}

        event: tool_use_input_partial
        data: {"id":"toolu_x","partialInput":"{\\"q\\":\\"orphan\\"}"}

        event: error
        data: {"code":"upstream_timeout","message":"provider timed out"}


        """

        let turn2SSE = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_use_start
        data: {"id":"toolu_x","name":"search"}

        event: tool_use
        data: {"id":"toolu_x","name":"search","input":{"q":"clean"}}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """

        // MockURLProtocol uses a single static handler. Vend turn1 first,
        // turn2 second using a captured counter.
        let counter = TurnCounter()
        let session = MockURLProtocol.install { _ in
            let n = counter.next()
            return n == 0 ? .sse(turn1SSE) : .sse(turn2SSE)
        }
        let provider = MetabindAgentProvider(
            baseURL: Self.baseURL,
            apiKey: "test-api-key",
            orgId: "org_abc",
            projectId: "proj_xyz",
            conversationId: nil,
            urlSession: session
        )

        // Turn 1: drain the stream so the orphan tool_use_start is left
        // unresolved on the actor (it shouldn't be, but pre-fix it was).
        _ = await collect(provider.stream(
            messages: [.user("first")], tools: nil, systemPrompt: nil
        ))

        // Turn 2: fresh stream. Index must reset to 0; id mapping must
        // not collide with the orphan from turn 1.
        let events2 = await collect(provider.stream(
            messages: [.user("second")], tools: nil, systemPrompt: nil
        ))

        let firstStart = events2.compactMap { event -> Int? in
            if case .toolCallStart(let i, _, _) = event { return i }
            return nil
        }.first
        #expect(firstStart == 0, "turn 2 must allocate index 0; got \(String(describing: firstStart)) — actor-state leak from turn 1")

        // And the terminal `tool_use` for toolu_x in turn 2 must take the
        // streaming path (using turn 2's freshly allocated id mapping),
        // emitting `toolCallArgumentsFinal` — not the legacy synth which
        // would re-emit `toolCallStart`.
        let starts2 = events2.filter { if case .toolCallStart = $0 { true } else { false } }
        #expect(starts2.count == 1, "turn 2 must not synthesize a second toolCallStart — id mapping resolved cleanly")
    }

    @Test func partialForUnknownIdIsDropped() async {
        defer { MockURLProtocol.uninstall() }
        // Defensive: if the agent ever emits a `tool_use_input_partial`
        // without a matching `tool_use_start` (protocol violation), we
        // must not silently route it under the latest open block or to a
        // synthetic index — we drop it.
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_use_start
        data: {"id":"toolu_real","name":"search"}

        event: tool_use_input_partial
        data: {"id":"toolu_GHOST","partialInput":"{\\"q\\":\\"x\\"}"}

        event: tool_use
        data: {"id":"toolu_real","name":"search","input":{"q":"r"}}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))

        // No toolCallArgumentDelta should have been emitted — the ghost
        // partial was dropped. Sequence: start → argsFinal → stop → done.
        let deltas = events.filter {
            if case .toolCallArgumentDelta = $0 { true } else { false }
        }
        #expect(deltas.isEmpty)
        if case .toolCallArgumentsFinal(_, let args) = events[1] {
            #expect(args == .object(["q": .string("r")]))
        } else {
            Issue.record("expected .toolCallArgumentsFinal at index 1, got \(events[1])")
        }
    }

    @Test func toolResultRoundTripsStructuredContent() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_start
        data: {"conversationId":"conv-1"}

        event: tool_result
        data: {"toolUseId":"toolu_1","content":[{"type":"text","text":"72°F sunny"}],"structuredContent":{"temp":72,"condition":"sunny"}}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("weather?")], tools: nil, systemPrompt: nil
        ))

        let result = try? events.first(where: {
            if case .toolResult = $0 { return true }
            return false
        })
        try? #require(result != nil)

        if case .toolResult(let id, let content, let structured, let isError) = events.first(where: {
            if case .toolResult = $0 { return true }
            return false
        }) ?? .error(URLError(.unknown)) {
            #expect(id == "toolu_1")
            #expect(content == "72°F sunny")
            #expect(isError == false)
            // structuredContent preserved verbatim
            #expect(structured == .object(["temp": .number(72), "condition": .string("sunny")]))
        } else {
            Issue.record("expected .toolResult")
        }
    }

    @Test func toolResultWithIsErrorTrue() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: tool_result
        data: {"toolUseId":"toolu_1","content":[{"type":"text","text":"boom"}],"isError":true}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))

        if case .toolResult(_, let content, _, let isError) = events.first(where: {
            if case .toolResult = $0 { return true }
            return false
        }) ?? .error(URLError(.unknown)) {
            #expect(content == "boom")
            #expect(isError == true)
        } else {
            Issue.record("expected .toolResult")
        }
    }

    @Test func providerSwitchEmitsEvent() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: provider_switch
        data: {"from":"anthropic","to":"openai","reason":"rate_limit","attempt":2}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))

        if case .providerSwitch(let from, let to, let reason) = events[0] {
            #expect(from == "anthropic")
            #expect(to == "openai")
            #expect(reason == "rate_limit")
        } else {
            Issue.record("expected .providerSwitch, got \(events[0])")
        }
    }

    // MARK: - Stream termination

    @Test func messageStopEndTurnEndsStream() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))
        #expect(events.count == 1)
        if case .done(let r) = events[0] { #expect(r == .endTurn) } else { Issue.record() }
    }

    @Test func messageStopMaxTokensEndsStream() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_stop
        data: {"stopReason":"max_tokens"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))
        if case .done(let r) = events[0] { #expect(r == .maxTokens) } else { Issue.record() }
    }

    @Test func messageStopToolUseDoesNotEndStream() async {
        defer { MockURLProtocol.uninstall() }
        // tool_use stop mid-stream, followed by another turn and final end_turn.
        let sse = """
        event: text_delta
        data: {"text":"Let me check."}

        event: tool_use
        data: {"id":"toolu_1","name":"look","input":{}}

        event: message_stop
        data: {"stopReason":"tool_use"}

        event: tool_result
        data: {"toolUseId":"toolu_1","content":[{"type":"text","text":"ok"}]}

        event: text_delta
        data: {"text":"Done."}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))

        // Should see text, tool_use synthetics, tool_result, more text, final done.
        let doneEvents = events.filter {
            if case .done = $0 { return true }
            return false
        }
        #expect(doneEvents.count == 1, "stream should only emit .done once (the terminal end_turn)")
        if case .done(let r) = doneEvents.first ?? .error(URLError(.unknown)) {
            #expect(r == .endTurn)
        }
        // Everything through the final text_delta must have been seen.
        let texts = events.compactMap {
            if case .textDelta(let t) = $0 { return t }
            return nil as String?
        }
        #expect(texts == ["Let me check.", "Done."])
    }

    @Test func unknownStopReasonMapsToUnknown() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_stop
        data: {"stopReason":"refusal"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))
        if case .done(let r) = events[0] {
            #expect(r == .unknown("refusal"))
        } else {
            Issue.record()
        }
    }

    @Test func errorEventEndsStream() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: error
        data: {"code":"provider_error","message":"upstream went boom"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))
        #expect(events.count == 1)
        if case .error(let err) = events[0],
           let agentError = err as? AgentError,
           case .serverError(let code, let message) = agentError {
            #expect(code == "provider_error")
            #expect(message == "upstream went boom")
        } else {
            Issue.record("expected .error(AgentError.serverError), got \(events[0])")
        }
    }

    // MARK: - Framing

    @Test func heartbeatLinesAreSkipped() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        :heartbeat

        event: text_delta
        data: {"text":"hi"}

        :heartbeat

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))
        let texts = events.compactMap {
            if case .textDelta(let t) = $0 { return t }
            return nil as String?
        }
        #expect(texts == ["hi"])
    }

    @Test func malformedFrameDataIsDropped() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: text_delta
        data: not-valid-json

        event: text_delta
        data: {"text":"ok"}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let events = await collect(makeProvider(sse: sse).stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))
        let texts = events.compactMap {
            if case .textDelta(let t) = $0 { return t }
            return nil as String?
        }
        // malformed frame is silently dropped; only the valid text_delta comes through.
        #expect(texts == ["ok"])
    }

    // MARK: - Conversation id tracking

    @Test func captureConversationIdFromMessageStart() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_start
        data: {"conversationId":"conv-assigned"}

        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let provider = makeProvider(sse: sse)
        _ = await collect(provider.stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))
        let id = await provider.currentConversationId
        #expect(id == "conv-assigned")
    }

    @Test func resumedConversationSendsOnlyLatestUserMessage() async throws {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let provider = makeProvider(sse: sse, conversationId: "conv-existing")

        let history: [LLMMessage] = [
            .user("first"),
            .assistant(text: "first reply", toolCalls: []),
            .user("second"),
            .assistant(text: "second reply", toolCalls: []),
            .user("third"), // only this should be sent
        ]

        _ = await collect(provider.stream(
            messages: history, tools: nil, systemPrompt: nil
        ))

        let body = try #require(MockURLProtocol.capturedBody())
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["conversationId"] as? String == "conv-existing")
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1, "resumed conversations only send the newest user turn")
        #expect(messages[0]["content"] as? String == "third")
    }

    @Test func freshConversationSendsFullHistory() async throws {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let provider = makeProvider(sse: sse)

        let history: [LLMMessage] = [
            .user("hello"),
            .assistant(text: "hi", toolCalls: []),
            .user("continue"),
        ]

        _ = await collect(provider.stream(
            messages: history, tools: nil, systemPrompt: nil
        ))

        let body = try #require(MockURLProtocol.capturedBody())
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["conversationId"] == nil)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
    }

    /// The agent service rejects client-supplied tool protocol blocks with
    /// `bad_request` — a fresh-conversation replay must strip them. (A reset()
    /// racing the end of a streaming turn can orphan an assistant turn with
    /// tool calls into a cleared history; that history must still be sendable.)
    @Test func freshConversationStripsToolProtocolBlocks() async throws {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let provider = makeProvider(sse: sse)

        let history: [LLMMessage] = [
            .user("what's my net worth?"),
            .assistant(text: "Here you go.", toolCalls: [
                LLMToolCall(id: "toolu_1", name: "get_net_worth", arguments: .object([:])),
            ]),
            .toolResults([LLMToolResult(toolCallId: "toolu_1", content: "{}")]),
            .assistant(text: nil, toolCalls: [
                LLMToolCall(id: "toolu_2", name: "net_worth_trend", arguments: .object([:])),
            ]), // tool-only turn: dropped entirely
            .user("show me a graph"),
        ]

        _ = await collect(provider.stream(
            messages: history, tools: nil, systemPrompt: nil
        ))

        let body = try #require(MockURLProtocol.capturedBody())
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 3, "user, text-only assistant, user")

        let serialized = String(data: body, encoding: .utf8) ?? ""
        #expect(!serialized.contains("tool_use"))
        #expect(!serialized.contains("tool_result"))

        let assistant = try #require(
            messages.first(where: { $0["role"] as? String == "assistant" })
        )
        let blocks = try #require(assistant["content"] as? [[String: Any]])
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "text")
        #expect(blocks[0]["text"] as? String == "Here you go.")
    }

    @Test func resetConversationClearsId() async {
        defer { MockURLProtocol.uninstall() }
        let sse = """
        event: message_stop
        data: {"stopReason":"end_turn"}


        """
        let provider = makeProvider(sse: sse, conversationId: "conv-old")
        await provider.resetConversation()
        let id = await provider.currentConversationId
        #expect(id == nil)
    }

    // MARK: - HTTP errors

    @Test func nonOKStatusYieldsServerError() async {
        defer { MockURLProtocol.uninstall() }
        let body = """
        {"error":"rate_limit_exceeded","message":"Rate limit of 1000 requests/hour exceeded for project"}
        """
        let provider = makeProvider(response: .json(body, status: 429))
        let events = await collect(provider.stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))

        let errors = events.compactMap { event -> AgentError? in
            if case .error(let e) = event, let a = e as? AgentError { return a }
            return nil
        }
        #expect(errors.count == 1)
        if case .serverError(let code, let message) = errors.first {
            #expect(code == "rate_limit_exceeded")
            #expect(message.contains("1000 requests/hour"))
        } else {
            Issue.record("expected serverError, got \(String(describing: errors.first))")
        }
    }

    @Test func unauthorizedMapsToServerError() async {
        defer { MockURLProtocol.uninstall() }
        let body = #"{"error":"unauthorized","message":"Missing or invalid Authorization header"}"#
        let provider = makeProvider(response: .json(body, status: 401))
        let events = await collect(provider.stream(
            messages: [.user("x")], tools: nil, systemPrompt: nil
        ))
        if case .error(let err) = events.first ?? .textDelta(""),
           let a = err as? AgentError,
           case .serverError(let code, _) = a {
            #expect(code == "unauthorized")
        } else {
            Issue.record()
        }
    }

    // MARK: - Runtime characteristics

    @Test func runsToolsRemotelyIsTrue() {
        let provider = MetabindAgentProvider(
            baseURL: Self.baseURL,
            apiKey: "k",
            orgId: "o",
            projectId: "p"
        )
        #expect(provider.runsToolsRemotely)
    }

}
